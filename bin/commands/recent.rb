# @@recent
desc 'List recent entries'
default_value 10
arg_name 'COUNT'
command :recent do |c|
  c.example 'doing recent', desc: 'Show the 10 most recent entries across all sections'
  c.example 'doing recent 20', desc: 'Show the 20 most recent entries across all sections'
  c.example 'doing recent --section Currently 20', desc: 'List the 20 most recent entries from the Currently section'
  c.example 'doing recent --interactive 20', desc: 'Create a menu from the 20 most recent entries to perform batch actions on'

  c.desc 'Section'
  c.arg_name 'NAME'
  c.flag %i[s section], default_value: 'All'

  c.desc 'Select from a menu of matching entries to perform additional operations'
  c.switch %i[i interactive], negatable: false, default_value: false

  add_options(:output_template, c, default_template: 'recent')
  add_options(:time_display, c)
  add_options(:save, c)

  c.action do |global_options, options, args|
    section = @wwid.guess_section(options[:section]) || options[:section].cap_first

    unless global_options[:version]
      if Doing.setting('templates.recent.count')
        config_count = Doing.setting('templates.recent.count').to_i
      else
        config_count = 10
      end

      if options[:interactive]
        count = 0
      else
        count = args.empty? ? config_count : args[0].to_i
      end

      options[:times] = true if options[:totals]
      options[:sort_tags] = options[:tag_sort]

      template = Doing.setting('templates.recent').deep_merge(Doing.setting('templates.default'))
      tags_color = template.key?('tags_color') ? template['tags_color'] : nil

      opts = {
        sort_tags: options[:sort_tags],
        tags_color: tags_color,
        times: options[:times],
        totals: options[:totals],
        interactive: options[:interactive],
        output: options[:output],
        duration: options[:duration],
        config_template: options[:config_template],
        template: options[:template]
      }

      Doing::Pager.page @wwid.recent(count, section.cap_first, opts)
      opts[:count] = count
      opts[:title] = options[:title]
      Doing.config.save_view(opts.to_view, options[:save].downcase) if options[:save]
    end
  end
end
