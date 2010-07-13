class GoogleCheckoutNotificationController < ApplicationController
  protect_from_forgery :except => :create
  
  def create
    GoogleCheckout.handle_notification(request.raw_post, params)
  end
 
  private
  def create_spree_address_from_google_address(google_address)
    address = Address.new
    address.country = Country.find_by_iso(google_address.country_code)
    address.state = State.find_by_abbr(google_address.region)
    address.state_name = google_address.region unless address.state
    
    address_attrs = {
      :firstname  =>  google_address.contact_name[/^\S+/],
      :lastname   =>  google_address.contact_name[/\s.*/],
      :address1   =>  google_address.address1, 
      :address2   =>  google_address.address2,
      :city       =>  google_address.city,
      :phone      =>  google_address.phone,
      :zipcode    =>  google_address.postal_code
    }
    address.attributes = address_attrs
    address.save(false)
    address  
  end

end
