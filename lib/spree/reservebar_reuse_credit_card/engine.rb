module Spree
  module ReservebarReuseCreditCard
    class Engine < Rails::Engine
      isolate_namespace Spree
      engine_name 'spree_reservebar_reuse_credit_card'

      config.autoload_paths += %W(#{config.root}/lib)

      # use rspec for tests
      config.generators do |g|
        g.test_framework :rspec
      end
    
      initializer "spree.reservebar_reuse_credit_card.preferences", :before => :load_config_initializers do |app|
        Spree::ReservebarReuseCreditCard::Config = Spree::ReservebarReuseCreditCardConfiguration.new
      end
    

      def self.activate
        Dir.glob(File.join(File.dirname(__FILE__), "../../app/**/*_decorator*.rb")) do |c|
          Rails.configuration.cache_classes ? require(c) : load(c)
        end

        Spree::Ability.register_ability(::CreditCardAbility)
      end

      config.autoload_paths += %W(#{config.root}/lib)
      config.to_prepare &method(:activate).to_proc
      

      
    end
  end
end
