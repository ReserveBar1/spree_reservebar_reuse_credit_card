Spree::Admin::PaymentsController.class_eval do

  def create
    @payment = @order.payments.build(object_params)
    if @payment.payment_method.is_a?(Spree::Gateway) && @payment.payment_method.payment_profiles_supported? && params[:card].present? and params[:card] != 'new'
      @payment.source = Spree::Creditcard.find_by_id(params[:card])
    end

    if @order.completed? && @payment.amount < 0
      if @payment.payment_method.type == "Spree::Gateway::BraintreeGateway"
        gateway = @order.retailer.payment_method
        trans_id = @order.payments.where(state: 'completed').first.response_code
        amt = @payment.amount.to_f.abs.to_s
        response = gateway.refund(trans_id, amt)
        if response.is_a?(Braintree::SuccessfulResult)
          @payment.response_code = response.transaction.id
          @payment.state = 'completed'
          @payment.save
          flash[:notice] = 'Credit successfully created.'
        elsif response.is_a?(Braintree::ErrorResult)
          flash[:error] = 'Payment Errors: '
          flash[:error] += response.errors.map(&:message).to_sentence
        else
          flash[:error] = response
        end
        redirect_to admin_order_payments_path(@order) and return
      end
    end

    begin
      unless @payment.save
        respond_with(@payment) { |format| format.html { redirect_to admin_order_payments_path(@order) } }
        return
      end

      if @order.completed?
        @payment.process!
        flash.notice = flash_message_for(@payment, :successfully_created)

        respond_with(@payment) { |format| format.html { redirect_to admin_order_payments_path(@order) } }
      else
        #This is the first payment (admin created order)
        until @order.completed?
          @order.next!
        end
        flash.notice = t(:new_order_completed)
        respond_with(@payment) { |format| format.html { redirect_to admin_order_url(@order) } }
      end

    rescue Spree::Core::GatewayError => e
      flash[:error] = "#{e.message}"
      respond_with(@payment) { |format| format.html { redirect_to new_admin_payment_path(@order) } }
    end
  end

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
