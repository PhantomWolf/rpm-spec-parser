#!/usr/bin/env ruby
require 'json'
require 'optparse'

class InvalidSpecError < StandardError
  def initialize(msg)
    @msg = msg
  end

  def message
    return @msg
  end
end


class RpmSpecParser
  attr_reader :sections, :path

  SECTIONS            = ['%build', '%description', '%files', '%package',
                        '%install', '%prep', '%changelog', '%clean', '%check',
                        '%pre', '%post', '%preun', '%postun', '%verifyscript']

  CONDITIONAL_MACROS  = ['%if', '%else', '%endif']

  # Initialize the parser with a spec file
  # Params:
  #   spec_file - path of the spec file
  def initialize(spec_file)
    unless File.exists?(spec_file)
      raise InvalidSpecError.new("#{spec_file}: No such file")
    end
    @path   = spec_file
    @macros = {}
    @vars   = {}
  end

  # Detect macro type
  # Params:
  #   macro - Name of the macro, including the '%' character
  # Return:
  #   :conditional  - %if, %ifarch, %ifos, %else, %endif, etc
  #   :section      - %build, %prep, %files, etc
  #   nil           - considered as normal lines
  def macro_type(macro)
    # Conditional macros are ignored
    CONDITIONAL_MACROS.each do |pattern|
      return :conditional if macro.start_with?(pattern)
    end
    # Multi-line macros
    SECTIONS.each do |pattern|
      return :section if macro == pattern
    end
    # Other macros like %setup, %dir
    # will be considered as normal lines
    return nil
  end

  # Read and split spec file into sections
  # Each section starts with a section line, such as '%package doc', '%build'
  def read_sections
    @sections = []
    begin
      f = File.new(@path)
    rescue IOError => e
      raise IOError.new("Failed to read #{@path}")
    end
    section = ['%package'] # fake section for the main package
    f.each_line do |line|
      line = line.strip
      # Skip empty lines and comments
      next if line.length == 0 or line.start_with?('#')
      # Handle section lines(e.g. %package doc)
      section_name, args = line.start_with?('%') ? RpmSpecParser.get_section_and_args(line) : [nil, nil]
      if section_name.nil? or self.macro_type(section_name) != :section
        section.push(line)
      else
        # Save the previous section
        @sections.push(section.join("\n"))
        # Create a new section
        section = [line]
      end
    end
    # Save the last section
    @sections.push(section.join("\n"))
    # Close the file
    f.close
  end

  # Get value of macro
  def get_macro_value(macro)
  end

  # Expand macros to their values
  # Params:
  #   str - The string to be expanded
  # Return:
  #   ret - New string with macros expanded
  def expand_macros(str)
    ret = String.new(str)
    macros = ret.scan(/%\{[\w_\-:]\}/)
    macros.each do |key|
      if @macros.has_key?(key)
        ret.gsub!(/%\{#{key}\}/, @macros[key].to_s)
      end
    end
    return ret
  end

  # Split section line into section name and args
  # Params:
  #   line - The line to be parsed. Example: "%package doc"
  # Return:
  #   section - Macro name. Example: "%package"
  #   args    - Arguments, such as subpackage name, program to run
  def get_section_and_args(line)
    return nil, nil unless line.start_with?('%')
    line =~ /^(%\w+)\s*(.*)$/
    return nil, nil if $~.nil?
    # get macro name and its value
    section = $~[1]
    args = ($~[2].length == 0) ? nil : $~[2]
    return section, args
  end

  # Parse the args of a section
  # Params:
  #   section_name  - Name of the section, including the % sign at the beginning
  #   arg_list      - Array of argument list(similar to ARGV)
  # Return:
  #   parsed_args   - Parsed arguments, e.g. {:args => [], :opts => {}}
  def parse_section_args!(section_name, arg_list)
    parsed_args = {:args => [], :opts => {}}
    opt_parser = OptionParser.new do |opts|
      opts.on('-n', 'Do not include primary package name in subpackage name') do
        if ['%description', '%files', '%changelog',
            '%pre', '%preun', '%post', '%postun'].include?(section_name)
          parsed_args[:opts]['-n'] = true
        end
      end

      opts.on('-f [FILE]', String, 'Read file list from a file') do |file|
        if section_name == '%files'
          file = self.expand_macros(file)
          parsed_args[:opts]['-f'] = [] if parsed_args[:opts]['-f'].nil?
          parsed_args[:opts]['-f'].push(file)
        end
      end

      opts.on('-p [PROGRAM]', String, 'Program to run') do |program|
        if ['%pre', '%preun', '%post', '%postun'].include?(section_name)
          program = self.expand_macros(program)
          parsed_args[:opts]['-p'] = program
        end
      end
    end
    opt_parser.parse!(arg_list)
    # Ignore other options
    parsed_args[:args] = arg_list.select do |item|
      item.start_with?('-') ? false : true
    end
    parsed_args[:args].map! do |item|
      self.expand_macros(item)
    end
    return parsed_args
  end

  def get_subpackage_name(parsed_args, section)
    if parsed_args[:opts]['-n'] == true
    else
    end
  end

  def parse_section(macro_line)
    res = {}
    macro_line =~ /^(%\w+)\s*(.*)$/
    if $~.nil?
      raise InvalidSpecError.new("#{@path}: Invalid macro line #{macro_line}")
    end
    # get macro and its args
    res['name'] = $~[1]
    args = ($~[2].length == 0) ? nil : $~[2]
    unless args.nil?
      no_name = false
      array = args.split(' ')
      i = 0
      while i < array.length
        if array[i] == '-p'
          res[array[i]] = array[i+1]
          i += 1
        elsif array[i] == '-n'
          no_name = true
        end
        i += 1
      end
    end
  end
end

puts RpmSpecParser.parse_section_args('%files', '-f list -f baka  -n mydoc'.split(' '))
