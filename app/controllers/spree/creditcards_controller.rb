module Spree
  class CreditcardsController < Spree::BaseController
    ssl_allowed
    respond_to :js, :html

    def destroy
      @creditcard = Spree::Creditcard.find(params["id"])
      authorize! :destroy, @creditcard

      # TODO: think about the necessity of deleting payment profiles here.
      # I'm thinking we want to always leave them alone

      @creditcard.deleted_at = Time.now
      if @creditcard.save
        respond_with @creditcard
      else
        render template: 'spree/creditcards/destroy_error'
      end
    end

    def edit
      @creditcard = Spree::Creditcard.find(params[:id])
      if @creditcard.address.present?
        @address = @creditcard.address.dup
      else
        default_country = Spree::Country.find_by_name("United States")
        @address = @creditcard.build_address(:country => default_country)
      end
    end

    def update
      @creditcard = Spree::Creditcard.find(params[:id])

      if @creditcard.update_address(params[:address])
        flash[:notice] = I18n.t(:successfully_updated, :resource => I18n.t(:address))
      else
      end
      redirect_back_or_default(account_path)
    end
  end
end
