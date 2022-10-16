# frozen_string_literal: true

module Wallaby
  class ActiveRecord
    # Modal decorator for {Wallaby::ActiveRecord}
    class ModelDecorator < ::Wallaby::ModelDecorator
      # Data types to exclude for {#index_field_names}
      INDEX_EXCLUSIVE_DATA_TYPES = %w[
        binary citext hstore json jsonb tsvector xml
        blob mediumblob longblob text mediumtext longtext
      ].freeze

      # Classes to exclude for {#show_field_names}
      SHOW_EXCLUSIVE_CLASS_NAMES = %w[ActiveStorage::Attachment ActiveStorage::Blob].freeze

      # Fields to exclude for {#form_field_names}
      FORM_EXCLUSIVE_DATA_TYPES = %w[created_at updated_at].freeze

      # Original metadata information of the primative and association fields
      # pulling out from the ActiveRecord model.
      #
      # It needs to be frozen so that we can keep the metadata intact.
      # @example sample fields metadata:
      #   model_decorator.fields
      #   # =>
      #   {
      #     # general field
      #     id: { name: 'id', type: 'integer', label: 'Id' },
      #     # association field
      #     category: {
      #       name: 'category',
      #       type: 'belongs_to',
      #       label: 'Category',
      #       is_association: true,
      #       is_through: false,
      #       has_scope: false,
      #       foreign_key: 'category_id',
      #       class: Category
      #     }
      #   }
      # @return [ActiveSupport::HashWithIndifferentAccess] metadata
      def fields
        # NOTE: Need to check the database and table's existence before building up the metadata
        # so that the database creation and migration related task can be executed.
        @fields ||= ::ActiveSupport::HashWithIndifferentAccess.new.tap do |hash|
          next hash.default = {} unless @model_class.table_exists?

          hash.merge! general_fields
          hash.merge! association_fields
          hash.except!(*foreign_keys_from_associations)
        end.freeze
      rescue ::ActiveRecord::NoDatabaseError
        Hash.new({}).with_indifferent_access
      end

      # A copy of {#fields} for index page
      # @return [ActiveSupport::HashWithIndifferentAccess] metadata
      def index_fields
        @index_fields ||= Utils.clone fields
      end

      # A copy of {#fields} for show page
      # @return [ActiveSupport::HashWithIndifferentAccess] metadata
      def show_fields
        @show_fields ||= Utils.clone fields
      end

      # A copy of {#fields} for form (new/edit) page
      # @return [ActiveSupport::HashWithIndifferentAccess] metadata
      def form_fields
        @form_fields ||= Utils.clone fields
      end

      # @return [Array<String>] a list of field names for index page (note: only primitive SQL types are included).
      def index_field_names
        @index_field_names ||=
          index_fields.reject do |_field_name, metadata|
            metadata[:is_association] \
              || INDEX_EXCLUSIVE_DATA_TYPES.include?(metadata[:type])
          end.keys
      end

      # @return [Array<String>] a list of field names for show page (note: **ActiveStorage** fields are excluded).
      def show_field_names
        @show_field_names ||=
          show_fields.reject do |_field_name, metadata|
            SHOW_EXCLUSIVE_CLASS_NAMES.include? metadata[:class].try(:name)
          end.keys
      end

      # @return [Array<String>] a list of field names for form (new/edit) page
      #   (note: timestamps fields (e.g. created_at/updated_at) and complex relation fields are excluded).
      def form_field_names
        @form_field_names ||=
          form_fields.reject do |field_name, metadata|
            field_name == primary_key \
              || FORM_EXCLUSIVE_DATA_TYPES.include?(field_name) \
              || metadata[:has_scope] || metadata[:is_through]
          end.keys
      end

      # @return [ActiveModel::Errors] errors for resource
      def form_active_errors(resource)
        resource.errors
      end

      # @return [String] primary key for the resource
      def primary_key
        @primary_key ||= @model_class.primary_key
      end

      # To guess the title for resource.
      #
      # It will go through the fields and try to find out the one that looks
      # like a name or text representing this resource. Otherwise, it will fall
      # back to primary key.
      # @param resource [Object]
      # @return [String] the title of given resource
      def guess_title(resource)
        resource.try title_field_finder.find
      end

      protected

      # @return [Wallaby::ActiveRecord::ModelDecorator::FieldsBuilder]
      def field_builder
        @field_builder ||= FieldsBuilder.new @model_class
      end

      # @return [Wallaby::ActiveRecord::ModelDecorator::TitleFieldFinder]
      def title_field_finder
        @title_field_finder ||=
          TitleFieldFinder.new @model_class, general_fields
      end

      # @!method general_fields
      #   (see Wallaby::ActiveRecord::ModelDecorator::FieldsBuilder#general_fields)
      #   @see Wallaby::ActiveRecord::ModelDecorator::FieldsBuilder#general_fields

      # @!method association_fields
      #   (see Wallaby::ActiveRecord::ModelDecorator::FieldsBuilder#association_fields)
      #   @see Wallaby::ActiveRecord::ModelDecorator::FieldsBuilder#association_fields
      delegate :general_fields, :association_fields, to: :field_builder

      # Find out all the foreign keys for association fields
      # @param fields [Hash] metadata of fields
      # @return [Array<String>] a list of foreign keys
      def foreign_keys_from_associations(fields = association_fields)
        fields.each_with_object([]) do |(_field_name, metadata), keys|
          keys << metadata[:foreign_key] if metadata[:foreign_key]
          keys << metadata[:polymorphic_type] if metadata[:polymorphic_type]
          keys
        end
      end
    end
  end
end
