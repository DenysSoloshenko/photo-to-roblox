module Scene
  class ValidationError < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super(errors.map { |error| "#{error[:path]}: #{error[:message]}" }.join(", "))
    end
  end
end
