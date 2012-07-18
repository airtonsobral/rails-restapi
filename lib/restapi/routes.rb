module Restapi

  class Routes < Hash
    def mount(params = {:by => :controller})
      if params[:by] == :controller
        extract_routes_by_controller params[:rails_routes]
      else
        extract_routes_by_name params[:rails_routes]
      end
      self
    end
    
    private
    def extract_routes_by_controller(rails_routes)
      rails_routes.each do |route|
        if route.requirements[:controller]
          path = route.path
          http_method = route.verb
          action_name_lower_case = route.requirements[:action]
          controller_name_camelized = (route.requirements[:controller] + '_controller').camelize
          if controller_name_camelized && action_name_lower_case 
            self[controller_name_camelized] = {} if !self[controller_name_camelized]
            self[controller_name_camelized][action_name_lower_case.to_sym] = {:path => format_path(path), :http_method => http_method.to_sym}
          end
        end
      end
    end
    
    def extract_routes_by_name(rails_routes)
      rails_routes.each do |route|
        if route.requirements[:controller]
          name = route.name
          path = route.path
          http_method = route.verb
          self[name.to_sym] = {:path => format_path(path), :http_method => http_method.to_sym} if name
        end
      end
    end
    
    def format_path(path)
      path.gsub('(.:format)', '')
          .gsub('(.:ext)', '')
    end  
  end
  
end