Spree::Gateway::AuthorizeNet.class_eval do
  attr_accessible :name, :description, :environment, :display_on, :active, :type, :deleted_at, :preferred_test, :preferred_server, :preferred_test_mode
end
Spree::Gateway::AuthorizeNetCim.class_eval do
  attr_accessible :name, :description, :environment, :display_on, :active, :type, :deleted_at, :preferred_test, :preferred_server, :preferred_test_mode
end