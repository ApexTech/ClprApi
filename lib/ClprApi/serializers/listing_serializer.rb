module ClprApi
  module Serializers
    class ListingSerializer
      include ClprApi::Support::JsonAttributesSerializer

      S3_SOURCE_PATH = ENV.fetch("S3_SOURCE_PATH")
      IGNORED_FIELDS = ["photos_id", "photos_url", "photos_description"].freeze

      delegate :[], :fetch, to: :attrs

      alias_method :read_attribute_for_serialization, :send
      attr_reader :attrs, :solr_field_names

      def initialize(attrs)
        @solr_field_names = attrs.keys
        @attrs = prepare(field_sanitizer(attrs)).with_indifferent_access
      end

      def default_as_json
        attrs.as_json(except: IGNORED_FIELDS).merge(extra_fields: extra_fields).merge(image: image, images: images.map(&:as_json))
      end

      def method_missing(method, *args, &block)
        attrs[method]
      end

      def prepare(attrs)
        highlighted_until = attrs["highlighted_until"]
        youtube_id = attrs["youtube_id"]

        attrs["highlighted"] = highlighted_until.present? && Time.parse(highlighted_until) > Time.now

        if attrs["business_name"].present?
          attrs["business"] = Serializers::BusinessSerializer.new(Serializers::BusinessFromSerializedListing.new(attrs), root: nil)
        end

        if youtube_id.present?
          youtube_url = Support::Youtube::Url.new(youtube_id)
          attrs["youtube_id"] = youtube_url.embed_url if youtube_url.valid?
        end

        attrs
      end

      def extra_fields
        # Intentar obtener extra_fields como key directa
        direct_extra_fields = get_raw_extra_fields
        
        if direct_extra_fields.present?
          # Si existe como key directa, procesar y retornar
          custom_result = process_direct_extra_fields(direct_extra_fields)
          custom_result
        else
          # Fallback al método original que usa extra_fields_metadata
          @extra_fields ||= attrs.fetch("extra_fields_metadata", []).map { |field|
            Support::ExtraField.new(JSON.parse(field))
          }
        end
      end

      def main_image_url
        attrs["photos_main_url"].to_s
      end

      def image
        Serializers::ListingPhotoSerializer.new("#{S3_SOURCE_PATH}#{main_image_url}") if main_image_url.present?
      end

      def images
        Array(attrs["photos_url"]).map do |photo_url|
          Serializers::ListingPhotoSerializer.new("#{S3_SOURCE_PATH}#{photo_url}") if photo_url.present?
        end.compact
      end

      private

      def field_sanitizer(item)
        id = item.fetch("id")

        item.reduce({}) do |hash, (key, value)|
          hash.tap do |doc|
            doc[field_name_for(key)] = value
          end
        end.tap do |doc|
          doc["id"] = id

          doc.delete("")
        end
      end

      def field_name_for(key)
        field_name_parts = key.split("_")

        suffix = field_suffix_for(field_name_parts)

        "#{field_name_parts[0..-2].join("_")}#{suffix}"
      end

      def field_suffix_for(field_name_parts)
        if field_name_parts.last == "i" && field_name_parts[-2] != "id" && solr_field_names.include?("#{field_name_parts[0..-2].join("_")}_s")
          "_id"
        elsif field_name_parts.last == "im" && field_name_parts[-2] != "id"
          "_ids"
        end
      end

      def get_raw_extra_fields
        # Intentar obtener extra_fields de diferentes fuentes
        # 1. Buscar en attrs.extra_fields (como en el JSON que vimos)
        if attrs&.dig("extra_fields")
          result = attrs["extra_fields"]
          return result
        end
        
        # 2. Buscar en raw_item
        if instance_variable_defined?(:@raw_item)
          result = @raw_item["extra_fields"]
          return result if result.present?
        end
        
        # 3. Buscar en raw_items
        if instance_variable_defined?(:@raw_items)
          raw_item = @raw_items.find { |item| item["listing_id"] == attrs["id"].to_i }
          result = raw_item&.dig("extra_fields")
          return result if result.present?
        end
        
        # 4. Buscar en métodos públicos
        if respond_to?(:raw_item) && raw_item
          result = raw_item["extra_fields"]
          return result if result.present?
        end
        
        if respond_to?(:raw_items) && raw_items
          raw_item = raw_items.find { |item| item["listing_id"] == attrs["id"].to_i }
          result = raw_item&.dig("extra_fields")
          return result if result.present?
        end
        
        nil
      end

      def process_direct_extra_fields(direct_extra_fields)
        # Buscar metadata si está disponible
        metadata_raw = attrs["extra_fields_metadata"] || []
        # Parsear cada string JSON a hash
        metadata = metadata_raw.map { |m| m.is_a?(String) ? JSON.parse(m) : m }
        
        direct_extra_fields.map do |field_data|
          if field_data.is_a?(Hash)
            id = field_data["id"] || field_data[:id]
            meta_hash = metadata.find { |m| m["id"] == id } || {}
            type = meta_hash["type"] || field_data["type"] || field_data[:type] || "string"
            
            # Lógica combinada para el valor
            if type == "optionlist"
              raw_value = attrs[id] if attrs
              value = (!raw_value.nil? && raw_value != "") ? raw_value : meta_hash["value"]
            else
              value = meta_hash["value"]
            end
            value = "No disponible" if value.nil? || value == ""
            
            # Buscar el label en la metadata
            label = meta_hash["label"] || field_data["label"] || field_data[:label] || id.to_s.humanize
            primary = field_data["primary"] || field_data[:primary] || false
            slug = field_data["slug"] || field_data[:slug] || value.to_s.parameterize

            init_attrs = {
              "id" => id,
              "label" => label,
              "type" => type,
              "primary" => primary,
              "value" => value,
              "slug" => slug
            }
            Support::ExtraField.new(init_attrs)
          else
            id = field_data.to_s
            meta_hash = metadata.find { |m| m["id"] == id } || {}
            type = meta_hash["type"] || "string"
            
            if type == "optionlist"
              raw_value = attrs[id] if attrs
              value = (!raw_value.nil? && raw_value != "") ? raw_value : meta_hash["value"]
            else
              value = meta_hash["value"]
            end
            value = "No disponible" if value.nil? || value == ""
            label = meta_hash["label"] || id.humanize
            
            init_attrs = {
              "id" => id,
              "label" => label,
              "type" => type,
              "primary" => false,
              "value" => value,
              "slug" => value.to_s.parameterize
            }
            Support::ExtraField.new(init_attrs)
          end
        end
      end
    end
  end
end
