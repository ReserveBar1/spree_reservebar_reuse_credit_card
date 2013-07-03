module CardReuse
  
  # For reservebar, this has two modifications
  # 1: also show pending payments, since we only capture when the retailer accepts, but we may want to be able to use the card again right away
  # 2: TODO: pick the cards for a user based on either the current retailer or the first occurrence of a card
  def all_cards_for_user(user, retailer = false)
    return nil unless user
    if retailer
      creditcards = user.creditcards_for_retailer(retailer)
    else
      creditcards = user.unique_tokenized_cards
    end
  end
  
  def all_cards_for_user_faster(user)
    return nil unless user

    payments = Spree::Payment.joins(:order).where('spree_orders.completed_at IS NOT NULL').where('spree_orders.user_id' => user.id).order('spree_orders.created_at').where('spree_payments.source_type' => 'Spree::Creditcard').where('spree_payments.state' => ['pending', 'completed']).includes(:source)

    payments.map do |payment| 
      src = payment.source

      # some payment gateways use only one of these?  stripe possibly?
      if (src.gateway_payment_profile_id.nil? && src.gateway_customer_profile_id.nil?) || src.deleted?
        nil
      else
        src
      end
    end.compact.uniq
  end
  
  def all_cards_for_user_original(user)
    return nil unless user

    payments = Spree::Payment.joins(:order).where('spree_orders.completed_at IS NOT NULL').where('spree_orders.user_id' => user.id).order('spree_orders.created_at').where('spree_payments.source_type' => 'Spree::Creditcard').where('spree_payments.state' => 'completed')

    payments.map do |payment| 
      src = payment.source

      # some payment gateways use only one of these?  stripe possibly?
      if (src.gateway_payment_profile_id.nil? && src.gateway_customer_profile_id.nil?) || src.deleted?
        nil
      else
        src
      end
    end.compact.uniq
  end
  
end


