# frozen_string_literal: true

require 'kaminari'

module Modulorails

  # Author: varaby_m@modulotech.fr
  # generic class to build relation for model
  # should stay dry
  # result is self
  class ListWorker < BasicWorker

    # default results per page count
    DEFAULT_PER_PAGE = 10
    # orders
    ORDER_ASC = 'asc'
    ORDER_DESC = 'desc'

    class << self

      # method to find item with relation by id or condition appending the filter
      def find(id_or_condition, **options)
        # apply options, but override pagination and order skips to be set
        list = call(**options, skip_pagination: true, skip_order: true)
        # condition should be a hash, so if ID is passed make it Hash {id: ID}
        condition = id_or_condition.is_a?(Hash) ? id_or_condition : { id: id_or_condition }
        # retrieve first record by condition
        list.relation.find_by(condition)
      end

    end

    # optional attributes for relation
    require_attributes :filter, :page, :per_page, :order_field, :order_direction,
                       :skip_order, :skip_pagination,
                       optional: true

    # initialize default values
    set_callback :initialize, :after do
      # relation is model
      @relation = model.all
      # first page
      @page ||= 1
      # default per page for limit
      @per_page ||= DEFAULT_PER_PAGE
      # default order id
      @order_field ||= :id
      # default order direction ascending
      @order_direction = reverse_order? ? ORDER_DESC : ORDER_ASC
    end

    # expose relation for outer usage
    attr_reader :relation

    # worker entry
    def call
      # prepare the relation
      prepare_relation!
      # filter the relation
      filter_relation!
      # paginate the relation if it is not skipped
      paginate_relation! unless skip_pagination
      # order the relation
      order_relation! unless skip_order

      # return self
      self
    end

    protected

    # helper to get arel_table from the model
    delegate :arel_table, to: :model

    # additional preparation for relation
    # joins, selects, includes, etc.
    def prepare_relation!
    end

    # this method should be overrode
    def model
      raise NotImplementedError
    end

    # default permitted keys for filter hash
    def permitted_filter_keys
      %i[id]
    end

    # permitted filter with permitted keys applied
    def permitted_filter
      @filter = permit_attributes(filter, *permitted_filter_keys)
    end

    # method to filter the relation with simple where(filter) applied
    # you can add model's custom logic by overriding this method
    def filter_relation!
      # apply only if filter is present
      @relation = relation.where(permitted_filter) if filter.present?
    end

    # method to paginate the relation
    def paginate_relation!
      @relation = relation.page(page).per(per_page)
    end

    # model to use for relation sort
    def order_model
      # use model by default
      model
    end

    # method to order the relation
    def order_relation!
      # get the field for order
      field = order_model.arel_table[order_field]
      # apply reverse order for field if direction descending
      field = field.desc if reverse_order?
      # apply order to relation
      @relation = relation.order(field)
    end

    private

    # check if order is descending
    def reverse_order?
      order_direction.to_s == ORDER_DESC
    end

  end

end
