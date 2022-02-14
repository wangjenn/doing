# frozen_string_literal: true

module Doing
  # A collection of Changes
  class Changes
    attr_reader :changes
    attr_writer :changes_only

    def initialize(lookup: nil, search: nil, changes_only: false)
      @changes_only = changes_only
      changelog = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'CHANGELOG.md'))
      raise 'Error locating changelog' unless File.exist?(changelog)

      @content = IO.read(changelog)
      parse_changes(lookup, search)
    end

    def latest
      if @changes_only
        @changes[0].changes_only.force_encoding('utf-8')
      else
        @changes[0].to_s.force_encoding('utf-8')
      end
    end

    def to_s
      if @changes_only
        @changes.map(&:changes_only).join().force_encoding('utf-8')
      else
        @changes.map(&:to_s).join("\n\n").force_encoding('utf-8')
      end
    end

    private

    def parse_changes(lookup, search)
      change_rx = /(?<=\n|\A)### (\d+\.\d+\.\d+(?:\w*))(.*?)(?=\n### |\Z)/m
      @changes = @content.scan(change_rx).each_with_object([]) do |m, a|
        next if m[0].nil? || m[1].nil?

        a << Change.new(m[0], m[1].strip)
      end

      lookup(lookup) unless lookup.nil?
      search(search) unless search.nil?
    end

    def lookup(lookup_version)
      range = []

      if lookup_version =~ /([\d.]+) *-+ *([\d.]+)/
        m = Regexp.last_match
        lookup("> #{m[1]}")
        lookup("< #{m[2]}")
      elsif lookup_version.scan(/[<>]/).count > 1
        params = lookup_version.scan(/[<>] [\d.]+/)
        params.each { |query| lookup(query) }
      else
        comp = case lookup_version
               when /(<|prior|before|older)/
                 :older
               when />|since|after|newer/
                 :newer
               else
                 :equal
               end
        version = Version.new(lookup_version)

        @changes.select! do |change|
          change.version.compare(version, comp)
        end
      end
    end

    def search(query)
      @changes.map do |c|
        c.entries = c.search_entries(query)
      end

      @changes.delete_if { |c| c.nil? || c.entries.nil? }
    end
  end
end
