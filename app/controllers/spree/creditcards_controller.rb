module Spree
  class CreditcardsController < Spree::BaseController
    ssl_allowed
    respond_to :js

    def destroy
      @creditcard = Spree::Creditcard.find(params["id"])
      @user = @creditcard.user
      authorize! :destroy, @creditcard

      # TODO: think about the necessity of deleting payment profiles here.
      # I'm thinking we want to always leave them alone

      if @creditcard.save
        delete_matching_credit_cards
        respond_with @creditcard
      else
        render template: 'spree/creditcards/destroy_error'
      end

    end

    private

    def matching_credit_cards
      conditions = {:month => @creditcard.month,
                    :year => @creditcard.year,
                    :cc_type => @creditcard.cc_type,
                    :last_digits => @creditcard.last_digits,
                    :first_name => @creditcard.first_name,
                    :deleted_at => nil}
      @user.creditcards.find(:all, :conditions => conditions)
    end

    def delete_matching_credit_cards
      matching_credit_cards.each do |cc|
        cc.deleted_at = Time.now
        cc.save
      end
    end
  end

end
