module ClprApi
  module Solr
    class Query
      module QueryParams
        def search_param
          params[:keywords]
        end

        def area_param
          params[:area].to_s.split(",")
        end

        def sort_by_param
          params[:order]
        end

        def source_param
          @source_param ||= splitable_or_enumerable_from(:source)
        end

        def category_param
          @category_param ||= splitable_or_enumerable_from(:category)
        end

        def _filters_category_param
          @_filters_category_param ||= splitable_or_enumerable_from(:filters_category_param)
        end

        def filters_category_param
          _filters_category_param.present? ? _filters_category_param : category_param
        end

        def search_filter
          "( ( ( title_s:'#{search_param}' )^5.5 OR ( description_s:'#{search_param}' )^2.5 OR ( id:*#{search_param}* )^1.0 ) )" if search_param.present?
        end

        def category_negation_filter
          "{!tag=category}((-category_slug_sm:(servicios-masajes)))" if category_param.include?("servicios")
        end

        def category_filter
          "{!tag=category}( ( category_slug_sm: (#{category_param.join(" OR ")}) ) )" if category_param.present?
        end

        def source_filter
          "{!tag=source}( ( source_s: (#{source_param.join(" OR ")}) ) )" if source_param.present?
        end

        def area_filter
          "{!tag=area}( ( secondary_areas_slug_sm: (#{area_param.join(" OR ")}) ) )" if area_param.present?
        end

        def sort
          @sort ||= "#{sort_by} #{direction}".downcase.strip
        end

        def root_filters
          [
            search_filter,
            category_filter,
            category_negation_filter,
            area_filter,
            source_filter,
          ].compact
        end

        def dynamic_filters
          []
        end

        def search_query
          root_filters.concat(dynamic_filters).compact
        end

        def sort_by
          sorter_klass.for(sort_by_param)
        end

        def sorter_klass
          @sorter_klass ||= params[:highlighted] == "true" ? RandomSorter : QuerySorter
        end

        def direction
          @direction ||= QuerySorter.direction_for(params.fetch(:direction, sort_by_param))
        end

        def start
          (page - 1) * limit
        end

        def page
          params.fetch(:page) { 1 }.to_i
        end

        def limit
          params.fetch(:limit) { 10 }.to_i
        end

        def highlighted?
          [true, "true"].include?(params.fetch(:highlighted, false))
        end

        private

        def splitable_or_enumerable_from(key)
          params[key].is_a?(Enumerable) ? params[key] : params[key].to_s.split(",")
        end
      end
    end
  end
end
