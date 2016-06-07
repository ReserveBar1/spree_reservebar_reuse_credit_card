require 'card_reuse'

Spree::CheckoutController.class_eval do
  include CardReuse

  private

  def before_payment
    current_order.payments.destroy_all if request.put?
    current_order.bill_address = Spree::Address.default
    @cards = all_cards_for_user(@order.user, @order.retailer)
    @cards = @cards.reject { |c| c.expired? }
  end

  # we are overriding this method in order to substitue in the exisiting card information
  # since we are also storing the billing address with the existing credit cards, we need to get it from the credit card
  # and dump it into the order:bill_address_id
  def object_params
    # For payment step, filter order parameters to produce the expected nested attributes for a single payment and its source, discarding attributes for payment methods other than the one selected
    if @order.payment?
      if params[:payment_source].present? && source_params = params.delete(:payment_source)[params[:order][:payments_attributes].first[:payment_method_id].underscore]

        if params[:order][:bill_address_id].present? && params[:order][:bill_address_id] != '0'
          source_params[:address_id] = params[:order][:bill_address_id]
        elsif params[:bill_address].present?
          @order.bill_address_attributes = params[:bill_address]
          bill_address = @order.bill_address
          if bill_address && bill_address.valid?
            @order.update_attribute_without_callbacks(:bill_address_id, bill_address.id)
            bill_address.update_attribute(:user_id, current_user.id) if current_user
            params[:order].delete(:bill_address_id)
            object_params.delete(:bill_address_id)
          else
            raise Exceptions::NewBillAddressError
          end
          @order.reload
          source_params[:address_id] = @order.bill_address_id
        else
          raise 'No Billing Address'
        end

        if params[:existing_card]
          creditcard = Spree::Creditcard.find(params[:existing_card])
          authorize! :manage, creditcard
          params[:order][:payments_attributes].first[:source] = creditcard
          params[:order][:bill_address_id] = creditcard.address_id
        else
          source_params[:device_data] = params[:device_data]
          params[:order][:payments_attributes].first[:source_attributes] = source_params
        end
      end
      if params[:order].present? && params[:order][:payments_attributes].present?
        params[:order][:payments_attributes].first[:amount] = @order.total
      end
    end
    params[:order]
  end

end
