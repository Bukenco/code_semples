class CouponUsageService
  include Umg::ErrorsFormat

  attr_accessor :errors, :response_code, :current_account, :code

  def initialize(params, customer)
    @params = params
    @customer = customer.main_customer
    @single_code = single_coupon_code?
    @coupon_code = get_coupon_code_object
    @pharmacy = Pharmacy.find(@params[:pharmacy_id]) if @params[:pharmacy_id].present?
    @errors = []
  end

  def coupon_usage_json_view
    @medicaments.json_view
  end

  def call
    validate_coupon_usage
    send_usage_to_purchase
  end

  def update_coupon_usage
    @coupon_code.update({ is_used: true, used_at: DateTime.now  })
    @errors.concat(fill_errors(@coupon_code))
  end

  private

  def get_coupon_code_object
    if @single_code
      CouponCode.where(code: @params[:coupon_code]&.upcase, is_used: false, deactivated: false)&.first
    else
      CouponCode.find_by_code(@params[:coupon_code]&.upcase)
    end
  end

  def single_coupon_code?
    CouponCode.find_by_code(@params[:coupon_code]&.upcase)&.coupon_promotion&.coupon_code_type&.id_name.eql?("single_code")
  end

  def send_usage_to_purchase
    return if errors.any?
    @medicaments = PurchaseCartService.new(@params, @customer)
    @medicaments.add
  end

  def validate_coupon_usage
    valid_coupon_code?
    valid_single_coupon_limit?
    valid_coupon_activity?
    valid_coupon_dates?
    valid_coupon_usage_limit?
  end

  def valid_single_coupon_limit?
    return if !@single_code || errors.any?
    if @coupon_code.coupon_promotion.single_code_usage_limit <= CouponCode.where(code: @coupon_code.code, is_used: true).count
      fill_custom_errors(self, :password, :invalid, I18n.t("custom.errors.invalid_limit_single_coupon_code"))
    end
  end

  def valid_coupon_code?
    if @coupon_code.nil?
      fill_custom_errors(self, :password, :invalid, I18n.t("custom.errors.invalid_coupon_code")) if !@single_code
      fill_custom_errors(self, :password, :invalid, I18n.t("custom.errors.invalid_limit_single_coupon_code")) if @single_code
    end
  end

  def valid_coupon_activity?
    return if errors.any?
    if @coupon_code&.is_used
      fill_custom_errors(self, :password, :invalid, I18n.t("custom.errors.coupon_code_already_used"))
    end
  end

  def valid_coupon_dates?
    return if errors.any?
    if @coupon_code.coupon_promotion.start_time > DateTime.now || @coupon_code.coupon_promotion.end_time < DateTime.now || !@coupon_code&.coupon_promotion&.is_active
      fill_custom_errors(self, :password, :invalid, I18n.t("custom.errors.invalid_usage_date"))
    end
  end

  def valid_coupon_usage_limit?
    return if errors.any?
    used_coupons
    if @array_of_ids.length >= @coupon_code.coupon_promotion.usage_limit_per_account
      fill_custom_errors(self, :password, :invalid, I18n.t("custom.errors.invalid_usage_limit"))
    end
  end

  def used_coupons
    @array_of_ids = []
    used_codes = MedicamentOrder
                      .select('coupon_codes.id')
                      .joins(medicament_order_components: [medicament_used_coupon: [coupon_code: :coupon_promotion]])
                      .where(umg_customer_id: @customer.id,
                             medicament_used_coupons: { is_canceled: false },
                             coupon_promotions: { id: @coupon_code.coupon_promotion_id })
                      .as_json

    used_codes.map{ |obj| @array_of_ids << obj["id"] }
    @array_of_ids.uniq!
  end
end