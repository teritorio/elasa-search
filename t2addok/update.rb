#!/usr/bin/ruby

require 'yaml'
require 'json'
require 'webcache'


@download_cache = WebCache.new(life: '6h', dir: '/data/cache')


def write_sjson(json, index)
    File.open(json, 'w') { |f|
        index.each{ |row|
            JSON.dump(row, io=f)
            f.write("\n")
        }
    }
end


def menu_name(m)
    (m['menu_group'] && m['menu_group']['name']['fr']) || (m['category'] && m['category']['name']['fr'])
end

def menu_parent_name(map, m)
    parent_id = m['parent_id']
    if parent_id then
        parent = map[parent_id]

        # Not name from first level bloc
        if parent['parent_id'] then
            menu_name(parent)
        end
    end
end

def any_hidden(map, m)
    if m then
        return m['hidden'] || any_hidden(map, m['parent_id'] && map[m['parent_id']])
    else
        false
    end
end

def menu(url, project_theme, json)
    menu = JSON.parse(@download_cache.get(url).content)
    map = Hash[menu.collect{ |m| [m['id'], m] }]
    get_name = lambda { |m| m['category'] && m['category']['name']['fr'] }

    filters_store = {}
    index = menu.select{ |m| m['category'] && !any_hidden(map, m) }.each{ |m|
        map[m['parent_id']][:non_leaf] = true if m['parent_id']
    }.select{ |m| !m[:non_leaf] }.collect{ |m|
        name = menu_name(m)
        next if !name
        parent_name = menu_parent_name(map, m)

        filters = m['category'] && m['category']['filters'] && m['category']['filters'].collect{ |filter|
            property = filter['property']
            values = if filter['type'] == 'boolean' then
                [[nil, filter['name']['fr'] || property]]
            else
                filter["values"].map{ |v| [v['value'], v['name'] && v['name']['fr'] || v['value']] }
            end
            values = values.filter{ |v| !v[1].nil? }
            filters_store[property] = (filters_store[property] || {}).update(Hash[values])
            values.map{ |value| [property, *value] }
        }.flatten(1) || []

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
                icon: m['menu_group']&.[]('icon') || m['category']&.[]('icon'),
                color: m['menu_group']&.[]('color') || m['category']&.[]('color'),
                filter_property: filter_property,
                filter_value: filter_value,
            }
        }
    }.compact.flatten(1)

    write_sjson(json, index)
    filters_store
end


def pois(url, project_theme, filters_store, json)
    pois = JSON.parse(@download_cache.get(url).content)
    filters_store_keys = filters_store.keys

    index = pois['features'].select{ |poi|
        poi['geometry']['coordinates'][0] > -180 && poi['geometry']['coordinates'][0] < 180 &&
        poi['geometry']['coordinates'][1] > -90 && poi['geometry']['coordinates'][1] < 90
    }.collect{ |poi|
        p = poi['properties']
        name = p['name'] && p['name'] != '' ? p['name'] : nil
        class_label = p['editorial']['class_label']['fr']
        name_class = name && class_label != name ? class_label + ' ' + name : nil

        name_filters = p.keys.intersection(filters_store_keys).collect{ |property|
            values = p[property]
            values = [values] if !values.kind_of?(Array)
           ([nil] + values).collect{ |value| filters_store[property][value] }
        }.flatten.compact.uniq

        {
            id: p['metadata']['id'],
            project_theme: project_theme,
            type: 'poi',
            importance: name_class ? 0.6 : 0.5,
            lon: poi['geometry']['coordinates'][0],
            lat: poi['geometry']['coordinates'][1],
            name: ([
                name,
                name_class,
            ] + name_filters.map{ |name_filter| "#{name} #{name_filter}" }).compact,
            street: p['addr:street'],
            postcode: p['addr:postcode'],
            city: p['addr:city'],
            icon: p['display']['icon'],
            color: p['display']['color'],
        }
    }.select{ |m| m[:name].size > 0 }

    write_sjson(json, index)
end


config = YAML.load(File.read(ARGV[0]))
config['sources'].each { |project, source|
    api = source['api']
    source['themes'].each { |theme|
        project_theme = "#{project}-#{theme}"

        menu_url = "#{api}/#{project}/#{theme}/menu"
        pois_url = "#{api}/#{project}/#{theme}/pois"

        menu = "/data/#{project_theme}-menu"
        pois = "/data/#{project_theme}-pois"

        filters_store = menu(menu_url, project_theme, "#{menu}.sjson")
        pois(pois_url, project_theme, filters_store, "#{pois}.sjson")
    }
}
