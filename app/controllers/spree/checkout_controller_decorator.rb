require 'card_reuse'

module Spree
  CheckoutController.class_eval do
    include CardReuse

    private

    def before_payment
      current_order.payments.destroy_all if request.put?
      current_order.bill_address = Spree::Address.default
      @cards = all_cards_for_user(@order.user, @order.retailer)
    end
    
    # Set the credit cards address to the order's bill address, if the credit card does not yet 
    # have the bill address set. This should only happen when the user enters a new credit card.
    # Normally, this should happen in after_payment, but that somehow gets called one step too early, after the delivery step.
    # So we push it to the before_confirm callback instead.
    def before_confirm
      source = current_order.payment.source
      if source.is_a?(Spree::Creditcard) && (source.address_id == nil)
        source.update_attribute(:address_id, current_order.bill_address_id)
      end
    end

    # we are overriding this method in order to substitue in the exisiting card information
    # since we are also storing the billing address with the existing credit cards, we need to get it from the credit card
    # and dump it into the order:bill_address_id
    def object_params
      # For payment step, filter order parameters to produce the expected nested attributes for a single payment and its source, discarding attributes for payment methods other than the one selected
      if @order.payment?
        if params[:payment_source].present? && source_params = params.delete(:payment_source)[params[:order][:payments_attributes].first[:payment_method_id].underscore]
          if params[:existing_card]
            creditcard = Spree::Creditcard.find(params[:existing_card])
            authorize! :manage, creditcard
            params[:order][:payments_attributes].first[:source] = creditcard
            params[:order][:bill_address_id] = creditcard.address_id
          else
            params[:order][:payments_attributes].first[:source_attributes] = source_params
          end
        end
        if (params[:order][:payments_attributes])
          params[:order][:payments_attributes].first[:amount] = @order.total
        end
      end
      params[:order]
    end

  end
end
