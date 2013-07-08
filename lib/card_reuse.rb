module CardReuse
  
  # For reservebar, this has two modifications
  # 1: also show pending payments, since we only capture when the retailer accepts, but we may want to be able to use the card again right away
  def all_cards_for_user_only_for_retailer(user, retailer = false)
    return nil unless user
    if retailer
      creditcards = user.creditcards_for_retailer(retailer)
    else
      creditcards = user.unique_tokenized_cards
    end
  end
  
  # get all cards for a user and a retailer, but include cards only tokenized for another retailer
  def all_cards_for_user(user, retailer = false)
    return nil unless user
    if retailer
      # get cards tokenized for this retailer:
      creditcards = user.creditcards_for_retailer(retailer)
      # get all unique tokenized cards, so we can show cards tokenized for another retailer too
      creditcards_all_retailers = user.unique_tokenized_cards
      # merge them together, using the ones for this retailer preferred
      creditcards_all_retailers.each do |creditcard|
        unless creditcards.map(&:card_data).include?(creditcard.card_data)
          creditcards << creditcard
        end
      end
      creditcards
    else
      creditcards = user.unique_tokenized_cards
    end
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


