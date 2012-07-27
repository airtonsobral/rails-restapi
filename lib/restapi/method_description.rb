require 'set'
module Restapi

  class MethodDescription
  
    class Api
      
      attr_accessor :short_description, :api_url, :http_method, :need_update, :route_name
      
      def initialize(params)
        method = params[:method]
        path = params[:path]
        @short_description = params[:short_desc]
        
        # There is no way to use routes right on the Api initialization, because
        # of the class caching on production.
        # Because of that, the http_method and api_url is going to be updated when
        # the method_description json is firstly generated (calling the updated_apis)
        if path
          if path.is_a?(Symbol)
            @route_name = path
            @need_update = true
          else
            @api_url = create_api_url(path)
            @http_method = method.to_s  
          end
        else
          @need_update = true
        end
      end
      
      # Here the blank apis are filled with data extracted from the routes.rb.
      def self.updated_apis(apis, controller, method)
        apis.each do |api|
          if api.need_update
            route = api.route_name.blank? ? Restapi.routes_by_controller[controller][method] : Restapi.routes_by_name[api.route_name]
            if route
              api.api_url = route[:path]
              api.http_method = route[:http_method]
              api.need_update = false
            else
              puts "RailsRestAPI Warning - There was a problem finding the route for api: #{api.to_json}"
            end
          end
        end
      end
      
      private
      
      def create_api_url(path)
        "#{Restapi.configuration.api_base_url}#{path}"
      end

    end

    attr_reader :errors, :full_description, :method, :resource, :apis, :inline_params_suffix, :examples, :see
    
    def initialize(method, resource, app)
      @method = method
      @resource = resource
      @apis = app.get_api_args
      @see = app.get_see
     
      desc = app.get_description || ''
      @full_description = Restapi.markup_to_html(desc)
      @errors = app.get_errors
      @params_ordered = app.get_params
      @inline_params_suffix = extract_inline_params_suffix @params_ordered
      @examples = app.get_examples
      
      @examples = load_generated_examples + @examples
      @examples += load_recorded_examples

      parent = @resource.controller.superclass
      if parent != ActionController::Base
        @parent_resource = parent.controller_name
      end
      @resource.add_method(id)
    end

    def id
      "#{resource._id}##{method}"
    end

    def params
      params_ordered.reduce({}) { |h,p| h[p.name] = p; h }
    end

    def params_ordered
      all_params = []
      # get params from parent resource description
      if @parent_resource
        parent = Restapi.get_resource_description(@parent_resource)
        merge_params(all_params, parent._params_ordered) if parent
      end

      # get params from actual resource description
      if @resource
        merge_params(all_params, resource._params_ordered)
      end

      merge_params(all_params, @params_ordered)
      all_params.find_all(&:validator)
    end
    
    def doc_url
      Restapi.full_url("#{@resource._id}/#{@method}")
    end

    def method_apis_to_json
      Restapi::MethodDescription::Api.updated_apis(@apis, @resource.controller.to_s, @method).each.collect do |api|
        {
          :api_url => api.api_url,
          :http_method => api.http_method.to_s,
          :short_description => api.short_description
        }
      end
    end

    def see_url
      if @see
        method_description = Restapi[@see]
        if method_description.nil?
          raise ArgumentError.new("Method #{@see} referenced in 'see' does not exist.")
        end 
        method_description.doc_url
      end
    end
    
    def see
      @see
    end

    def to_json
      {
        :doc_url => doc_url,
        :name => @method,
        :apis => method_apis_to_json,
        :inline_params_suffix => @inline_params_suffix,
        :full_description => @full_description,
        :errors => @errors,
        :params => params_ordered.map(&:to_json).flatten,
        :examples => @examples,
        :see => @see,
        :see_url => see_url
      }
    end

    private
    
    def extract_inline_params_suffix(params)
      suffix = "?"
      params.each do |param|
        if param.inline && param.type == :request
          suffix << "#{param.name}=#{param.validator.expected_type}&"
        end
      end
      suffix.chop # removing the last '&' if there is at least one inline parameter
                  # or remove the first '?' if there is no inline parameter at all
    end

    def merge_params(params, new_params)
      new_param_names = Set.new(new_params.map(&:name))
      params.delete_if { |p| new_param_names.include?(p.name) }
      params.concat(new_params)
    end

    def load_recorded_examples
      (Restapi.recorded_examples[id] || []).
        find_all { |ex| ex["show_in_doc"].to_i > 0 }.
        sort_by { |ex| ex["show_in_doc"] }.
        map { |ex| format_example(ex.symbolize_keys) }
    end
    
    # These examples are generated by the non-inline request/response params defined on the annotation
    def load_generated_examples
      ["Request: #{generate_json_example(:request)} \nResponse: #{generate_json_example(:response)}"]
    end

    def format_example_data(data)
      case data
      when Array, Hash
        JSON.pretty_generate(data).gsub(/: \[\s*\]/,": []").gsub(/\{\s*\}/,"{}")
      else
        data
      end
    end

    def format_example(ex)
      example = "#{ex[:verb]} #{ex[:path]}"
      example << "?#{ex[:query]}" unless ex[:query].blank?
      example << "\n" << format_example_data(ex[:request_data]).to_s if ex[:request_data]
      example << "\n" << ex[:code].to_s
      example << "\n" << format_example_data(ex[:response_data]).to_s if ex[:response_data]
      example
    end
    
    def generate_json_example(type)
      params_to_clean_json(@params_ordered.select{ |p| p.type == type })
    end
    
    def params_to_clean_json(params)
      hash = {}
      params.each{ |param| hash.merge!(param_to_simple_hash(param.to_json)) }
      hash.to_json
    end
    
    def param_to_simple_hash(param)
      if param[:params]
        childs_hash_merged = {}
        param[:params].each do |param_child|
          childs_hash_merged.merge!(param_to_simple_hash(param_child))
        end
        if param[:hash_array_container]
          return {param[:name] => [childs_hash_merged, childs_hash_merged]}
        else
          return {param[:name] => childs_hash_merged}
        end
      else
        return param[:inline] ? {} : {param[:name] => param[:expected_type]}
      end
    end

  end
  
end
