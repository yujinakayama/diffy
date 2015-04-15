require 'diff/lcs'
require 'diff/lcs/hunk'

module Diffy
  class RubyDiff
    ORIGINAL_DEFAULT_OPTIONS = {
      :source => 'strings',
      :include_diff_info => false,
      :include_plus_and_minus_in_html => false,
      :context => 10000,
      :allow_empty_diff => true,
    }

    UNSUPPORTED_OPTION_KEYS = [:diff]

    INFO_LINE_PATTERN = /^(---|\+\+\+|@@|\\\\)/

    class << self
      attr_writer :default_format
      def default_format
        @default_format || :text
      end

      # default options passed to new Diff objects
      attr_writer :default_options
      def default_options
        @default_options ||= ORIGINAL_DEFAULT_OPTIONS.dup
      end

    end
    include Enumerable
    attr_reader :string1, :string2, :options, :diff

    # supported options
    # +:diff+::    A cli options string passed to diff
    # +:source+::  Either _strings_ or _files_.  Determines whether string1
    #              and string2 should be interpreted as strings or file paths.
    # +:include_diff_info+::    Include diff header info
    # +:include_plus_and_minus_in_html+::    Show the +, -, ' ' at the
    #                                        beginning of lines in html output.
    def initialize(string1, string2, options = {})
      unsupported_option_keys = options.keys & UNSUPPORTED_OPTION_KEYS

      unless unsupported_option_keys.empty?
        raise ArgumentError, "Unsupported option: #{unsupported_option_keys.join(', ')}."
      end

      @options = self.class.default_options.merge(options)
      if ! ['strings', 'files'].include?(@options[:source])
        raise ArgumentError, "Invalid :source option #{@options[:source].inspect}. Supported options are 'strings' and 'files'."
      end
      @string1, @string2 = string1, string2
    end

    def diff
      @diff ||= begin
        case options[:source]
        when 'strings'
          paths = []
          sources = [string1, string2].map(&:split)
        when 'files'
          paths = [string1, string2]
          sources = paths.map { |path| File.readlines(path).map { |line| line.chomp } }
        end

        output = diff_lcs(*sources)
        output.force_encoding('ASCII-8BIT') if output.respond_to?(:valid_encoding?) && !output.valid_encoding?

        if output.empty?
          unless options[:allow_empty_diff]
            lines = sources.first
            output = lines.map { |line| " #{line}\n" }.join
          end
        else
          output = diff_info(*paths) + output
        end

        output
      end
    end

    def each(&block)
      lines = if options[:include_diff_info]
                diff.each_line
              else
                diff.each_line.reject {|x| x =~ INFO_LINE_PATTERN }
              end

      if block
        lines.each(&block)
      else
        lines
      end
    end

    def each_chunk
      old_state = nil
      chunks = inject([]) do |cc, line|
        state = line.each_char.first
        if state == old_state
          cc.last << line
        else
          cc.push line.dup
        end
        old_state = state
        cc
      end

      if block_given?
        chunks.each{|chunk| yield chunk }
      else
        chunks.to_enum
      end
    end

    def to_s(format = nil)
      format ||= self.class.default_format
      formats = Format.instance_methods(false).map{|x| x.to_s}
      if formats.include? format.to_s
        enum = self
        enum.extend Format
        enum.send format
      else
        raise ArgumentError,
          "Format #{format.inspect} not found in #{formats.inspect}"
      end
    end

    private

    def diff_lcs(lines1, lines2, modification_times: [])
      diffs = ::Diff::LCS.diff(lines1, lines2)
      return '' if diffs.empty?

      # Loop over hunks. If a hunk overlaps with the last hunk, join them.
      # Otherwise, print out the old one.
      previous_hunk = nil
      previous_file_length_difference = 0
      output = ''

      diffs.each do |piece|
        begin
          hunk = ::Diff::LCS::Hunk.new(
            lines1,
            lines2,
            piece,
            options[:context],
            previous_file_length_difference
          )

          previous_file_length_difference = hunk.file_length_difference

          next unless previous_hunk

          overlapped = hunk.merge(previous_hunk)
          next if track_context? && overlapped

          output << previous_hunk.diff(:unified) << "\n"
        ensure
          previous_hunk = hunk
        end
      end

      output << previous_hunk.diff(:unified) << "\n"

      output
    end

    def diff_info(*paths)
      files = if paths.empty?
                %w(a b).map { |name| { name: name, time: Time.now } }
              else
                paths.map { |path| { name: path, time: File.stat(path).mtime } }
              end

      files.first[:marker] = '---'
      files.last[:marker] = '+++'

      files.each_with_object('') do |file, info|
        info << "#{file[:marker]} #{file[:name]}\t#{format_time(file[:time])}\n"
      end
    end

    def format_time(time)
      time.localtime.strftime('%Y-%m-%d %H:%M:%S.%N %z')
    end

    def track_context?
      options[:context]
    end
  end
end
