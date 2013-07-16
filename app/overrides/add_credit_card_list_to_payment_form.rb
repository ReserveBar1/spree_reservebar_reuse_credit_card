if Spree::ReservebarReuseCreditCard::Config.enabled == true
Deface::Override.new(
                     :name => 'add_credit_card_list_to_payment_form',
                     :virtual_path => 'spree/checkout/payment/_gateway_without_bill_address',
                     :insert_before => '[data-hook=name_on_card]',
                     :partial =>'spree/checkout/payment/existing_cards'
)
end
