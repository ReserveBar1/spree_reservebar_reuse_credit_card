Spree::Admin::PaymentsController.class_eval do

  private

  def load_data
    @amount = params[:amount] || load_order.total
    @payment_methods = Spree::PaymentMethod.available(:back_end)
    if @payment and @payment.payment_method
      @payment_method = @payment.payment_method
    else
      @payment_method = @payment_methods.first
    end
    @previous_cards = @order.creditcards.with_payment_profile.where(bt_merchant_id: @order.retailer.bt_merchant_id)
  end

end
