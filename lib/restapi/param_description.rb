module Restapi

  # method parameter description
  # 
  # name - method name (show)
  # desc - description
  # required - boolean if required
  # inline - boolean if the parameter is used inline on a URL (ex: /malls?something=12)
  # validator - Validator::BaseValidator subclass
  class ParamDescription

    attr_reader :name, :desc, :required, :allow_nil, :type, :inline, :hash_array_container, :validator

    attr_accessor :parent
    
    def initialize(name, *args, &block)
      
      if args.size > 1 || !args.first.is_a?(Hash)
        validator_type = args.shift || nil
      else
        validator_type = nil
      end
      @type = args.pop
      options = args.pop || {}
      
      @name = name
      @desc = Restapi.markup_to_html(options[:desc] || '')
      @required = options[:required] || false
      @inline = options[:inline] || false
      @allow_nil = options[:allow_nil] || false
      @hash_array_container = options[:hash_array_container] || false
      
      block = auto_load_params(name, options[:auto_load_params], block) if options[:auto_load_params]
      
      @validator = nil
      unless validator_type.nil?
        @validator = 
          Validator::BaseValidator.find(self, validator_type, options, block)
        raise "Validator not found." unless validator
      end
    end

    def validate(value)
      return true if @allow_nil && value.nil?
      unless @validator.valid?(value)
        raise ArgumentError.new(@validator.error)
      end
    end

    def full_name
      name_parts = parents_and_self.map(&:name)
      if parent && parent.hash_array_container
        top = name_parts.pop
        name_parts << ""
        name_parts << top
      end
      return ([name_parts.first] + name_parts[1..-1].map { |n| "[#{n}]" }).join("")
    end

    # returns an array of all the parents: starting with the root parent
    # ending with itself
    def parents_and_self
      ret = []
      if self.parent
        ret.concat(self.parent.parents_and_self)
      end
      ret << self
      ret
    end
    
    def auto_load_params(name, option, block)
      begin
        extra_block = Proc.new {
          if option
            model_class = name.to_s.camelize.singularize.constantize
            if option == true
              attrs = model_class.columns
            else
              attrs = model_class.send option
            end
            attrs.each do |c|
              name = c.name
              begin
                type = c.type.to_s.camelize.constantize
              rescue
                type = String
              end
              param name, type, :desc => name
            end
          end
        }
        block_temp = block
        block = Proc.new {
          instance_exec(&block_temp) if block_temp
          instance_exec(&extra_block)
        }
      rescue
        puts "RailsRestAPI Warning - There was a problem auto loading child parameters for the #{name} param"
      end
      
      block
    end

    def to_json
      if validator.is_a? Restapi::Validator::HashValidator
        {
          :name => name.to_s,
          :full_name => full_name,
          :type => type,
          :description => desc,
          :required => required,
          :inline => inline,
          :allow_nil => allow_nil,
          :hash_array_container => hash_array_container,
          :validator => validator.to_s,
          :expected_type => validator.expected_type,
          :params => validator.hash_params_ordered.map(&:to_json)
        }
      else
        {
          :name => name.to_s,
          :full_name => full_name,
          :type => type,
          :description => desc,
          :required => required,
          :inline => inline,
          :allow_nil => allow_nil,
          :hash_array_container => hash_array_container,
          :validator => validator.to_s,
          :expected_type => validator.expected_type
        }
      end
    end

  end

end
