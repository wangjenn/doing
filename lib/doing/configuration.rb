# frozen_string_literal: true

module Doing
  ##
  ## @brief      Configuration object
  ##
  class Configuration
    attr_reader :settings

    attr_writer :ignore_local

    MissingConfigFile = Class.new(RuntimeError)

    DEFAULTS = {
      'autotag' => {
        'whitelist' => [],
        'synonyms' => {}
      },
      'doing_file' => '~/what_was_i_doing.md',
      'current_section' => 'Currently',
      'config_editor_app' => nil,
      'editor' => ENV['DOING_EDITOR'] || ENV['GIT_EDITOR'] || ENV['EDITOR'],
      'editor_app' => nil,
      'paginate' => false,
      'never_time' => [],
      'never_finish' => [],

      'templates' => {
        'default' => {
          'date_format' => '%Y-%m-%d %H:%M',
          'template' => '%date | %title%note',
          'wrap_width' => 0,
          'order' => 'asc'
        },
        'today' => {
          'date_format' => '%_I:%M%P',
          'template' => '%date: %title %interval%note',
          'wrap_width' => 0,
          'order' => 'asc'
        },
        'last' => {
          'date_format' => '%-I:%M%P on %a',
          'template' => '%title (at %date)%odnote',
          'wrap_width' => 88
        },
        'recent' => {
          'date_format' => '%_I:%M%P',
          'template' => '%shortdate: %title (%section)',
          'wrap_width' => 88,
          'count' => 10,
          'order' => 'asc'
        }
      },

      'export_templates' => {},

      'views' => {
        'done' => {
          'date_format' => '%_I:%M%P',
          'template' => '%date | %title%note',
          'wrap_width' => 0,
          'section' => 'All',
          'count' => 0,
          'order' => 'desc',
          'tags' => 'done complete cancelled',
          'tags_bool' => 'OR'
        },
        'color' => {
          'date_format' => '%F %_I:%M%P',
          'template' => '%boldblack%date %boldgreen| %boldwhite%title%default%note',
          'wrap_width' => 0,
          'section' => 'Currently',
          'count' => 10,
          'order' => 'asc'
        }
      },
      'marker_tag' => 'flagged',
      'marker_color' => 'red',
      'default_tags' => [],
      'tag_sort' => 'name',
      'include_notes' => true
    }

    def initialize(file = nil, options: {})
      if file
        cf = File.expand_path(file)
        # raise MissingConfigFile, "Config not found (#{cf})" unless File.exist?(cf)

        @config_file = cf
      end

      @settings = configure(options)
    end

    def additional_configs
      @additional_configs ||= find_local_config
    end

    # Static: Produce a Configuration ready for use in a Site.
    # It takes the input, fills in the defaults where values do not exist.
    #
    # user_config - a Hash or Configuration of overrides.
    #
    # Returns a Configuration filled with defaults.
    def from(user_config)
      Util.deep_merge_hashes(DEFAULTS, Configuration[user_config].stringify_keys)
    end

    def config_file
      @config_file ||= File.join(Util.user_home, '.doingrc')
    end

    def config_file=(file)
      @config_file = file
    end

    ##
    ## @brief      Read user configuration and merge with defaults
    ##
    ## @param      opt   (Hash) Additional Options
    ##
    def configure(opt = {})
      @ignore_local = opt[:ignore_local] if opt[:ignore_local]

      config = read_config.dup

      plugin_config = { 'plugin_path' => nil, 'command_path' => nil }
      command_path = config.dig('plugins', 'command_path') || File.join(Util.user_home, '.config', 'doing', 'commands')

      plugin_path = config.dig('plugins', 'plugin_path') || File.join(Util.user_home, '.config', 'doing', 'plugins')
      load_plugins(plugin_path)

      Plugins.plugins.each do |_type, plugins|
        plugins.each do |title, plugin|
          plugin_config[title] = plugin[:config] if plugin.key?(:config) && !plugin[:config].empty?
          config['export_templates'][title] ||= nil if plugin.key?(:templates)
        end
      end


      config.deep_merge({ 'plugins' => plugin_config })

      if !File.exist?(config_file) || opt[:rewrite]
        Util.write_to_file(config_file, YAML.dump(config), backup: true)
        Doing.logger.warn('Config:', "Config file written to #{config_file}")
      end

      Hooks.trigger :post_config, self

      config = local_config.deep_merge(config) unless @ignore_local

      Hooks.trigger :post_local_config, self

      config
    end

    private

    ##
    ## @brief      Read local configurations
    ##
    ## @return     Hash of config options
    ##
    def local_config
      return {} if @ignore_local

      local_configs = read_local_configs || {}

      if additional_configs&.count
        file_list = additional_configs.map { |p| p.sub(/^#{Util.user_home}/, '~') }.join(', ')
        Doing.logger.debug('Config:', "Local config files found: #{file_list}")
      end

      local_configs
    end

    def read_local_configs
      local_configs = {}

      begin
        additional_configs.each do |cfg|
          local_configs.deep_merge(Util.safe_load_file(cfg))
        end
      rescue StandardError
        Doing.logger.error('Config:', 'Error reading local configuration(s)')
      end

      local_configs
    end

    ##
    ## @brief      Reads a configuration.
    ##
    def read_config
      unless File.exist?(config_file)
        Doing.logger.info('Config:', 'Config file doesn\'t exist, using default configuration' )
        return {}.deep_merge(DEFAULTS)
      end

      begin
        user_config = Util.safe_load_file(config_file)
        if user_config.key?('html_template')
          user_config['export_templates'].deep_merge(user_config.delete('html_template'))
        end

        user_config['include_notes'] = user_config.delete(':include_notes') if user_config.key?(':include_notes')

        user_config.deep_merge(DEFAULTS)
      rescue StandardError => e
        Doing.logger.error('Config:', 'Error reading default configuration')
        Doing.logger.error('Error:', e.message)
        user_config = DEFAULTS
      end

      user_config
    end

    ##
    ## @brief      Finds a project-specific configuration file
    ##
    ## @return     (String) A file path
    ##
    def find_local_config
      dir = Dir.pwd

      local_config_files = []

      while dir != '/' && (dir =~ %r{[A-Z]:/}).nil?
        local_config_files.push(File.join(dir, '.doingrc')) if File.exist? File.join(dir, '.doingrc')

        dir = File.dirname(dir)
      end

      local_config_files.delete(config_file)

      local_config_files
    end

    def load_plugins(add_dir = nil)
      FileUtils.mkdir_p(add_dir) if add_dir

      Plugins.load_plugins(add_dir)
    end
  end
end
