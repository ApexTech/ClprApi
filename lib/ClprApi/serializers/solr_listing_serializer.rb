module ClprApi
  module Serializers
    class SolrListingSerializer < ActiveModel::Serializer
      attributes :id, :status, :glo_3d_id, :listing_id, :source, :source_id, :title, :description, :category_id, :area_id, :is_free, :is_sale, :sale_price_obo, :is_rent, :rent_price_start, :rent_price_end
      attributes :rent_price_obo, :is_barter, :lister_id, :highlighted_at, :highlighted_until, :expires_on, :created_at, :updated_at, :starts_on, :has_photos, :photos_count, :boost, :primary
      attributes :primary_fields_sm, :extra_fields_sm, :extra_fields_metadata_sm, :offering, :sale_price_start, :sale_price_end, :sale_price_unit, :rent_price_unit, :sale_price_unit_label
      attributes :rent_price_unit_label, :youtube_id, :location_string, :lister_key

      def sale_price_start
        positive?(object.sale_price_start)
      end

      def sale_price_end
        positive?(object.sale_price_end)
      end

      def rent_price_start
        positive?(object.rent_price_start)
      end

      def rent_price_end
        positive?(object.rent_price_end)
      end

      def title
        object.title.to_s.gsub(/[^[:print:]]/, "")
      end

      def description
        object.description.to_s.gsub(/[^[:print:]]/, "")
      end

      def sale_price_unit_label
        object.sale_price_unit_label.to_s
      end

      def rent_price_unit_label
        object.rent_price_unit_label.to_s
      end

      def id
        object.id_with_offering
      end

      def primary
        object.primary
      end

      def primary_fields_sm
        @primary_fields_sm ||= object.fields.primary_fields
      end

      def extra_fields_sm
        @extra_fields_sm ||= object.fields.field_ids
      end

      def extra_fields_metadata_sm
        @extra_fields_metadata_sm ||= object.fields.map { |field| SolrExtraFieldsMetadataSerializer.from_field(field).to_json }
      end

      def offering
        object.offering
      end

      def boost
        object.has_photos ? 1 : 0
      end

      def listing_id
        object.id
      end

      def starts_on
        object.starts_on || object.created_at
      end

      def glo_3d_id
        object.glo_3d_id || ""
      end

      def status
        object.status || "active"
      end

      def lister_key
        object.lister_key.to_s
      end

      private

      def positive?(value)
        value if value&.positive?
      end
    end
  end
end
