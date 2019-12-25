# frozen_string_literal: true

require 'active_support/callbacks'
require 'active_support/core_ext/object/blank'

module Modulorails

  # Author: varaby_m@modulotech.fr
  # BasicWorker would serve as an interface for all logic
  class BasicWorker

    include ActiveSupport::Callbacks
    # allow to add after_initialize callback
    # to be used instead of initialize overriding
    define_callbacks :initialize, only: :after

    class << self

      # reader for required attributes
      attr_reader :required_attributes
      # reader for optional attributes
      attr_reader :optional_attributes
      # reader for skipped attributes
      attr_reader :skipped_attributes

      # allow workers to declare what attributes they need
      def require_attributes(*attributes, optional: false)
        if optional
          @optional_attributes = attributes
        else
          @required_attributes = attributes
        end
      end

      # allow to skip nested required attributes
      def skip_attributes(*attributes)
        @skipped_attributes = attributes
      end

      # helper for processing entry point that returns call result
      def call(**args)
        # init instance and process
        new(**args).call
      end

      # this helper allows you to work with processed worker instance
      # result of call is written to #result
      def call_self(**args)
        # init instance
        new(**args).call_self
      end

    end

    # attribute to store call result
    attr_reader :result

    # instance initializer
    def initialize(**options)
      if instance_of?(BasicWorker)
        raise(NotImplementedError, 'Never use this class directly. Inherit!')
      end

      # collect arguments
      @options = options
      # init attributes
      @loaded_attributes = Set.new
      init_skip_attributes!
      init_attributes!
      init_optional_attributes!
      @loaded_attributes = nil

      run_callbacks :initialize
    end

    # processing entry point
    def call
      # children must override that method
      raise(NotImplementedError, 'Override #call method')
    end

    # entry for ::call_self
    def call_self
      # execute call and store to result
      @result = call
      # return self
      self
    end

    # check for errors after call self
    # equals true when no errors occurred
    def success?
      errors.blank?
    end

    # errors collected when executing call
    # :result.errors take precedence over @errors
    # so when :result responds to 'errors' it would be taken
    # even when @errors are present but :result.errors are blank
    # it means the success? would be true
    def errors
      # if result is instantiated and responds to "errors" (ActiveModel-like)
      if result.respond_to?(:errors)
        # return all errors array
        result.errors.full_messages
      # in other cases
      else
        # populate errors array
        @errors
      end
    end

    protected

    # small help from base class - collection of all arguments
    attr_reader :options

    # this method allows input both Hash and ActionController::Parameters
    # and cast them to hash
    # attributes are considered permitted when they come as hash
    # this can be used to bypass allowed fields
    def permit_attributes(attributes, *allowed_fields)
      # if attributes are of type hash or inherited from hash
      if attributes.is_a?(Hash)
        # return attribute copy
        attributes.deep_dup
      # when attributes respond to permit (like ActionController::Parameters)
      elsif attributes.respond_to?(:permit)
        # else permit allowed fields and cast to hash
        attributes.permit(*allowed_fields).to_h
      # unknown format
      else
        # replace with empty hash
        {}
      end
    end

    private

    # initialize required_attributes
    def init_attributes!
      iterate_classes do |target|
        init_attributes(target.required_attributes, false)
      end
    end

    # initialize optional_attributes
    def init_optional_attributes!
      iterate_classes do |target|
        init_attributes(target.optional_attributes, true)
      end
    end

    # init skipped attributes from all parent classes
    def init_skip_attributes!
      skipped_attributes = Set.new
      iterate_classes do |target|
        skipped_attributes += target.skipped_attributes || []
      end
      @loaded_attributes += skipped_attributes
    end

    def init_attributes(attrs, optional)
      # leave if there are none
      return unless attrs

      new_attributes = attrs.to_set - @loaded_attributes
      new_attributes.each do |attr|
        # :result attribute is used for ::call_self, so we don't allow
        # to require this attribute from the outside
        raise(ArgumentError, ':result attribute is reserved') if attr.to_sym == :result

        # retrieve value
        value = optional ? options[attr] : options.fetch(attr)
        # set value for attribute and store it
        instance_variable_set("@#{attr}", value)
        # skip adding reader if exists
        next if respond_to?(attr) || self.class.method_defined?(attr)

        # add reader for attribute
        self.class.module_eval do
          protected; attr_reader(attr) # rubocop:disable all
        end
      end

      @loaded_attributes += new_attributes
    end

    def iterate_classes
      # start from current class
      target = self.class
      loop do
        # yield class
        yield target

        # take target's superclass
        target = target.superclass
        # break loop if target is BasicWorker - root worker class
        break if target == BasicWorker
      end
    end

  end

end
