#!/usr/bin/ruby

require 'json'
require 'http'
require 'turf_ruby'


def http_get(url)
  fetch_http_headers = !ENV['FETCH_HTTP_HEADERS']&.empty? ? { ENV['FETCH_HTTP_HEADERS'] => true } : {}
  resp = HTTP.headers(fetch_http_headers).follow.get(url)
  if resp.status.success?
    resp.body
  else
    raise resp
  end
end

def write_sjson(json, index)
  File.open(json, 'w') { |f|
    index.each{ |row|
      JSON.dump(row, f)
      f.write("\n")
    }
  }
end

def property_i18n_to_text(property)
  return if property.nil? || property.empty?

  return property if property.is_a?(String) || property.is_a?(Numeric)

  if property.is_a?(Object)
    property = property['fr-FR'] || property['fr'] || property['en-US'] || property['en'] || property.first[1]
  end

  if property.is_a?(Array)
    property = property.join(' ')
  end

  property
end

def menu_name(m)
  (m['menu_group'] && m['menu_group']['name']['fr']) || (m['category'] && m['category']['name']['fr'])
end

def menu_parent_name(map, m)
  parent_id = m['parent_id']
  if parent_id
    parent = map[parent_id]

    # Not name from first level bloc
    menu_name(parent) if parent['parent_id']
  end
end

def any_hidden(map, m)
  if m
    m['hidden'] || any_hidden(map, m['parent_id'] && map[m['parent_id']])
  else
    false
  end
end

def menu(url, project_theme, json)
  menu = JSON.parse(http_get(url))
  map = menu.to_h{ |m| [m['id'], m] }

  search_indexed = []
  filters_store = {}
  index = menu.select{ |m| m['category'] && !any_hidden(map, m) }.each{ |m|
    map[m['parent_id']][:non_leaf] = true if m['parent_id']
  }.select{ |m| !m[:non_leaf] && m['category']['search_indexed'] }.collect{ |m|
    name = menu_name(m)
    next if !name

    parent_name = menu_parent_name(map, m)

    filters = (m.dig('category', 'filters') || []).collect{ |filter|
      property = filter['property']
      values = if filter['type'] == 'boolean'
          [[nil, filter['name'] && filter['name']['fr'] || property.join(' ')]]
        elsif filter['values'] && filter['values'].kind_of?(Array)
          filter['values'].map{ |v| [v['value'], property_i18n_to_text(v['name']) || v['value']] }
      end
      next unless values

      values = values.filter{ |v| !v[1].nil? }

      filters_store[property.join(':')] = (filters_store[property.join(':')] || {}).update(values.to_h)
      values.map{ |value| [property.join(':'), *value] }
    }.compact.flatten(1)

    search_indexed << m['id']

    ([[nil, nil, nil]] + filters).collect{ |filter_property, filter_value, filter_name|
      name_with_filter = filter_name ? "#{filter_name} (#{name})" : name
      {
        id: m['id'],
        project_theme: project_theme,
        type: 'menu_item',
        importance: filter_name ? 0.5 : 0.6,
        lon: 0,
        lat: 0,
        name: [
          name_with_filter,
          parent_name ? parent_name + ' ' + name_with_filter : nil
        ].compact,
        icon: m.dig('menu_group', 'icon') || m.dig('category', 'icon'),
        color: m.dig('menu_group', 'color') || m.dig('category', 'color'),
        filter_property: filter_property,
        filter_value: filter_value,
      }
    }
  }.compact.flatten(1)

  write_sjson(json, index)
  [search_indexed, filters_store, map]
end

def centroid(feature)
  if feature['geometry'] && feature['geometry']['coordinates']
    point = Turf.centroid(feature['geometry'].transform_keys(&:to_sym))
    feature['geometry']['type'] = point[:geometry][:type]
    feature['geometry']['coordinates'] = point[:geometry][:coordinates]
  end
  feature
end

def pois(url, menu_map, project_theme, search_indexed, filters_store, json)
  pois = JSON.parse(http_get(url))
  filters_store_keys = filters_store.keys.collect{ |k| k.start_with?('route:') || k.start_with?('addr:') ? k.split(':') : [k] }

  index = pois['features'].collect{ |poi|
    centroid(poi)
  }.select{ |poi|
    poi['properties']['metadata']['category_ids'] &&
      poi['properties']['metadata']['category_ids'].intersection(search_indexed).size > 0 &&
      poi['geometry'] && poi['geometry']['coordinates'] &&
      poi['geometry']['coordinates'][0] > -180 && poi['geometry']['coordinates'][0] < 360 &&
      poi['geometry']['coordinates'][1] > -90 && poi['geometry']['coordinates'][1] < 90
  }.collect{ |poi|
    p = poi['properties']
    name = property_i18n_to_text(p['name'])
    category_id = poi['properties']['metadata']['category_ids'].find{ |category_id| menu_map[category_id] }
    category = menu_map[category_id]['category']
    class_label = property_i18n_to_text(category.dig('editorial', 'class_label'))
    name_class = name && class_label && class_label != name ? class_label + ' ' + name : nil

    name_filters = filters_store_keys.collect{ |property|
      values = p.dig(*property)
      next if values.nil?

      values = [values] if !values.is_a?(Array)
      ([nil] + values).collect{ |value| property_i18n_to_text(filters_store[property.join(':')][value]) }
    }.compact.flatten.compact.uniq

    {
      id: p['metadata']['id'],
      project_theme: project_theme,
      type: 'poi',
      importance: name_class ? 0.6 : 0.5,
      lon: poi['geometry']['coordinates'][0].round(9),
      lat: poi['geometry']['coordinates'][1].round(9),
      name: ([
        name,
        name_class,
      ] + name_filters.map{ |name_filter| "#{name} #{name_filter}" }).compact.sort,
      street: p.dig('addr', 'street'),
      postcode: p.dig('addr', 'postcode'),
      city: p.dig('addr', 'city'),
      icon: category['icon'],
      color: p.dig('display', 'color_fill') || category['color_fill']
    }
  }.select{ |m| m[:name].size > 0 }

  write_sjson(json, index)
end


api = ARGV[0]
projects = JSON.parse(http_get(api))
projects.each_value{ |project|
  project['themes'].each_value{ |theme|
    project_theme = "#{project['slug']}-#{theme['slug']}"
    puts project_theme

    api_theme = "#{api}/#{project['slug']}/#{theme['slug']}/"
    menu_url = "#{api_theme}/menu.json"
    pois_url = "#{api_theme}/pois.geojson?as_point=true&short_description=true"

    menu = "/data/#{project_theme}-menu"
    pois = "/data/#{project_theme}-pois"

    begin
      search_indexed, filters_store, menu_map = menu(menu_url, project_theme, "#{menu}.sjson")
      pois(pois_url, menu_map, project_theme, search_indexed, filters_store, "#{pois}.sjson")
    rescue StandardError => e
      warn e.message
      warn e.backtrace.join("\n")
    end
  }
}
