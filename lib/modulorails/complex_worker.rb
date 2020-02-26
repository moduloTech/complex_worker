# frozen_string_literal: true

require 'active_support/core_ext/object/blank'

module Modulorails

  class ComplexWorker < BasicWorker

    class << self

      attr_writer :in_transaction, :mode

      def mode
        @mode ||= :rollback_end
      end

      def in_transaction
        @in_transaction.nil? ? true : @in_transaction
      end

      def steps
        @steps ||= []
      end

      def step(worker, options={})
        conditions, options =
          options.partition { |key, _value| key.in?(%i[if unless]) }.map(&:to_h)
        raise ArgumentError if conditions.keys.size > 1

        steps << [worker, options, conditions]
      end

    end

    attr_reader :results

    def call
      @errors = []
      _transaction do
        @results = steps.map do |step, attr_map, condition|
          next unless _condition?(condition)

          step.call_self(_map_attributes(attr_map)).tap do |step_result|
            unless step_result.success?
              raise ActiveRecord::Rollback if in_transaction && mode == :rollback_any

              @errors += step_result.errors
            end
          end
        end
      end

      @results&.last&.result
    end

    protected

    delegate :in_transaction, :mode, :steps, to: :class

    def _transaction
      if in_transaction
        ActiveRecord::Base.transaction do
          yield
          raise ActiveRecord::Rollback if mode == :rollback_end && !success?
        end
      else
        yield
      end
    end

    def _map_attributes(attr_map)
      options.merge(
        attr_map.map { |from, to| [to, options[from]] }.to_h
      )
    end

    def _condition?(condition)
      return true if condition.blank?

      statement, proc = condition.to_a.first
      proc = method(proc) if proc.is_a?(Symbol) || proc.is_a?(String)
      !!proc.call(self, options) ^ (statement == :unless) # rubocop:disable Style/DoubleNegation
    end

  end

end
