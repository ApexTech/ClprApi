module ClprApi
  module Solr
    class Query
      include Solr::Query::VirtualFields
      include Solr::Query::QueryParams
      include Solr::FieldSupport

      ACTIVE_LISTINGS_FILTER = [
        "{!tag=active}( ( expires_on_d: { NOW TO * } ) )",
        "{!tag=started}( ( starts_on_d: { * TO NOW } ) )", # this field is not getting populated at this point :starts_on
      ].freeze

      DEFAULT_FACETS = [
        "{!ex=offering key=offering}offering_s",
        "{!ex=has_photos key=has_photos}has_photos_b",
        "{!ex=category key=category}category_as_json_sm",
        "{!ex=area key=area}area_as_json_sm",
      ].freeze

      DEFAULT_STATS_FIELDS = [
        "price_start_f",
        "price_end_f",
      ].freeze

      DEFAULT_Q_PARAM = "*:*".freeze

      HIGHLIGHTED_FILTER = ["highlighted_until_d:[NOW TO *]"].freeze
      LISTABLE_TYPES = ["option", "optionlist", "boolean", "range"].freeze
      NUMERIC_TYPES = ["integer", "float", "range"].freeze
      DEFAULT_CACHE_TIME = 5.minutes

      delegate :total, to: :response

      attr_reader :params, :search_conditions, :selected_fields

      def initialize(search_conditions: [], params: {})
        @search_conditions = search_conditions
        @params = prepare_params(params)
        @selected_fields = [
          @params.delete(:fields) || DEFAULT_FIELDS,
          @params.delete(:extra_fields),
        ].compact.flatten.join(",")
      end

      def with_cache_ttl(cache_ttl)
        @cache_ttl = cache_ttl
        self
      end

      def response
        @response ||= Solr::Response.new(query_results, filterable_fields, filter_params, params)
      end

      def dynamic_filters
        super + filter_params.map(&:filter)
      end

      def filter_params
        @filter_params ||= FilterCollectionFromParams.new(filterable_fields + virtual_filters, params, category_param).valid
      end

      def filterable_fields
        @filterable_fields ||= FacetableField.all.select { |field| (filters_category_param & field.category_slugs).any? }
      end

      def query_params
        {
          q: DEFAULT_Q_PARAM,
          fq: facet_query,
          rows: limit,
          start: start,
          sort: sort,
        }.merge(stats).merge(facets)
      end

      def facet_query
        active_listings_filter + search_query + search_filters.flatten
      end

      def search_filters
        @search_filters ||= [
          search_conditions,
          highlighted_filter,
        ].flatten.compact
      end

      def limit_records_to_zero?
        limit.zero?
      end

      def total_pages
        @total_pages ||= limit_records_to_zero? ? 0 : (total / limit.to_f).ceil
      end

      def current_page
        @current_page ||= begin
            calc = limit_records_to_zero? ? 0 : (start / limit.to_f).ceil + 1
            (0..1).include?(calc) ? 1 : calc
          end
      end

      DEFAULT_FIELDS = [
        :score,
        :photos_main_url_s,
        :photos_count_i,
        :title_s,
        :id,
        :lister_id_i,
        :listing_id_i,
        :offering_s,
        :area_city_s,
        :area_country_s,
        :price_start_f,
        :price_end_f,
        :sale_price_start_f,
        :rent_price_start_f,
        :sale_price_unit_label_s,
        :rent_price_unit_label_s,
        :is_sale_b,
        :is_rent_b,
        :price_unit_s,
        :category_config_show_category_tree_b,
        :category_config_show_only_category_b,
        :category_config_show_price_b,
        :extra_fields_metadata_sm,
        :category_slug_s,
        :category_slug_sm,
        :category_label_s,
        :category_label_sm,
        :area_slug_s,
        :area_slug_sm,
        :highlighted_until_d,
        :youtube_id_s,
      ].map(&:to_s).join(",")

      def facets
        return {} unless facet_fields.present?

        {
          fl: selected_fields,
          facet: true,
          "facet.mincount": 1,
          "facet.method": :fc,
          "facet.field": facet_fields,
        }.merge(
          "f.category_as_json_sm.facet.limit" => -1,
          "f.category_as_json_sm.facet.mincount" => 1,
          "f.category_as_json_sm.facet.sort" => "lex",
          "f.category_as_json_sm.facet.missing" => "off",
          "f.area_as_json_sm.facet.limit" => -1,
          "f.area_as_json_sm.facet.mincount" => 1,
          "f.area_as_json_sm.facet.sort" => "lex",
          "f.area_as_json_sm.facet.missing" => "off",
          "f.area_as_json_sm.facet.offset" => 0,
        ).merge(facet_fields_attributes)
      end

      def facet_fields_attributes
        filterable_fields.select { |field| ["integer", "range"].include?(field.value) }.reduce({}) do |hash, field|
          solr_field = "#{field.field_id}#{solr_field_suffix_for(field)}"

          hash.merge(
            "f.#{solr_field}.facet.limit" => -1,
            "f.#{solr_field}.facet.mincount " => 1,
            "f.#{solr_field}.facet.offset" => 0,
            "f.#{solr_field}.facet.sort" => "count",
            "f.#{solr_field}.facet.missing" => "off",
          )
        end
      end

      def stats
        return {} unless stats_fields.present?

        {
          stats: true,
          "stats.field": stats_fields,
        }
      end

      def stats_fields
        @stats_fields ||= filterable_fields.map { |field|
          next unless NUMERIC_TYPES.include?(field.value)

          "#{field.field_id}#{solr_field_suffix_for(field)}"
        }.compact + DEFAULT_STATS_FIELDS
      end

      def facet_fields
        @facet_fields ||= DEFAULT_FACETS + filterable_fields.map { |field|
          if LISTABLE_TYPES.include?(field.value) || field.is_facetable
            case field.value
            when "option"
              "{!ex=#{field.field_id} key=#{field.field_id}}#{field.field_id}_json_s"
            when "optionlist"
              "{!ex=#{field.field_id} key=#{field.field_id}}#{field.field_id}_json_sm"
            else
              "{!ex=#{field.field_id} key=#{field.field_id}}#{field.field_id}#{solr_field_suffix_for(field)}"
            end
          end
        }.compact
      end

      def cache_key
        @cache_key ||= Digest::MD5.hexdigest([
          "CLPR-API-SOLR-SEARCH-RESULTS",
          self.class.name,
          query_params.to_s,
        ].join)
      end

      def cache_ttl
        @cache_ttl ||= ClprApi.default_cache_ttl
      end

      private

      def current_date_formatted
        @current_date_formatted ||= Date.today.strftime(DATE_FORMAT)
      end

      def active_listings_filter
        ["{!tag=active}( ( expires_on_d: { #{current_date_formatted} TO * } ) )"]
      end

      def prepare_params(_params = {})
        params = _params.dup.to_h.with_indifferent_access
        _filters = params.delete(:filters) || {}

        params.merge(_filters).with_indifferent_access
      end

      def raw_results
        Solr::Connection.instance.get(:select, params: query_params)
      end

      def cached_results
        ClprApi.cache.fetch(cache_key, expires_in: cache_ttl) do
          raw_results
        end
      end

      def query_results
        ClprApi.cache_enabled? ? cached_results : raw_results
      end

      def highlighted_filter
        HIGHLIGHTED_FILTER if highlighted?
      end
    end
  end
end
