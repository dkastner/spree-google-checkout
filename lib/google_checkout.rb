module GoogleCheckout
  extend self

  def handle_notification(post, params)
    frontend.tax_table_factory = TaxTableFactory.new
    handler = frontend.create_notification_handler

    begin
      notification = handler.handle(post)
      text = case notification.class
      when Google4R::Checkout::NewOrderNotification then
        new_order_notification(notification, params)
      when Google4R::Checkout::ChargeAmountNotification then
        charge_amount_notification(notification)
      else
        'ignoring unhandled notification type'
      end
      return text
    rescue Google4R::Checkout::UnknownNotificationType => e
      # This can happen if Google adds new commands and Google4R has not been
      # upgraded yet. It is not fatal.
      return 'ignoring unknown notification type'
    end
  end

  def new_order_notification(notification, params)
    order_number = params[:new_order_notification][:shopping_cart][:merchant_private_data][:order_number].strip.to_i
    begin
      order = Order.find_by_id(order_number)
    rescue ActiveRecord::RecordNotFound
      return 'Could not find that order - probably originated at Google'
    end
    
    unless order.allow_pay?
      order.user = current_user if current_user
      
      checkout_info = params[:new_order_notification]
      checkout_attrs = {
        :email => checkout_info[:email],
        :ip_address => request.env['REMOTE_ADDR']         
      }        
      order.checkout.update_attributes(checkout_attrs)
      
      order_attrs = {
        :adjustment_total => notification.order_adjustment.adjustment_total.cents.to_f / 100, 
        :buyer_id => notification.buyer_id,
        :financial_order_state => notification.financial_order_state, 
        :google_order_number =>  notification.google_order_number, 
        :gateway => 'Google Checkout'
      }        
      order.update_attributes(order_attrs)
      
      new_billing_address = 
        create_spree_address_from_google_address(notification.buyer_billing_address)
           
      order.checkout.update_attribute(:bill_address_id,  new_billing_address.id)        
      
      new_shipping_address = 
        create_spree_address_from_google_address(notification.buyer_shipping_address)
                
      order.shipment.update_attribute(:address_id,  new_shipping_address.id)
      
      ship_method = ShippingMethod.find_by_name(notification.order_adjustment.shipping.name)      
      order.shipment.update_attribute(:shipping_method, ship_method)
      order.checkout.shipping_method = ship_method
      
      order.complete!
    end
    'proccessed NewOrderNotification'
  end

  def charge_amount_notification(notification, params)
    order = Order.find_by_google_order_number(notification.google_order_number)
    payment = Payment.new(:amount => notification.latest_charge_amount)
    payment.order = order
    payment.save
    'proccessed ChargeAmountNotification'
  end

  def frontend
    return nil unless integration = Billing::GoogleCheckout.current
    gc_config = { 
      :merchant_id  => integration.preferred_merchant_id, 
      :merchant_key => integration.preferred_merchant_key, 
      :use_sandbox  => integration.preferred_use_sandbox }

    front_end = Google4R::Checkout::Frontend.new(gc_config)
    front_end.tax_table_factory = TaxTableFactory.new
    front_end
  end
end
