module Payments
  module StripeValue
    module_function

    def fetch(object, key)
      return nil if object.nil?
      if object.is_a?(Hash)
        return object[key] if object.key?(key)
        return object[key.to_s] if object.key?(key.to_s)
        return nil
      end
      return object.public_send(key) if object.respond_to?(key)
      if object.respond_to?(:to_h) && (values = object.to_h).is_a?(Hash)
        return values[key] if values.key?(key)
        return values[key.to_s] if values.key?(key.to_s)
      end

      nil
    end

    def metadata(object)
      value = fetch(object, :metadata)
      value.respond_to?(:to_h) ? value.to_h : (value || {})
    end

    def metadata_value(object, key)
      values = metadata(object)
      values[key.to_s] || values[key.to_sym]
    end
  end
end
