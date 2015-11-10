#!/usr/bin/env ruby
require 'json'

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

  # Supported options separated by comma
  # o   => -o
  # o:  => -o xxx
  # o:* => -o a -o b -o c ...
  # :   => xxx
  # :*  => xxx1 xxx2 xxx3 ...
  SECTION_OPTIONS = {
    '%description' => 'n,:',  # -n: Do NOT prefix the primary package name
    '%files' => 'f:*,n,:',     # -f: read file list from a file
    '%changelog' => 'n,:',
    '%pre' => 'p:,n,:',       # -p: Run given program
    '%preun' => 'p:,n,:',
    '%post' => 'p:,n,:',
    '%postun' => 'p:,n,:',
  }

  # Parse section line
  def self.parse_section(section_name, args)
    ret = {'name' => section_name}
    return ret if args.nil?
    # Parse args
    i = 0
    arg_list = args.split(' ')
    if self.class.SECTION_OPTIONS.has_key?(section_name)
      while i < arg_list.length
        i += 1
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
  def self.get_section_and_args(line)
    if not line.start_with?('%')
      return nil, nil
    end
    line =~ /^(%\w+)\s*(.*)$/
    if $~.nil?
      return nil, nil
    end
    # get macro name and its value
    section = $~[1]
    args = ($~[2].length == 0) ? nil : $~[2]
    return section, args
  end

  # Detect macro type
  # Params:
  #   macro - Name of the macro, including the '%' character
  # Return:
  #   :conditional  - %if, %ifarch, %ifos, %else, %endif, etc
  #   :section      - %build, %prep, %files, etc
  #   nil           - considered as normal lines
  def self.macro_type(macro)
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

  def initialize(spec_file)
    unless File.file?(spec_file)
      raise InvalidSpecError.new("#{spec_file}: Not an ordinary file")
    end
    unless File.readable?(spec_file)
      raise InvalidSpecError.new("#{spec_file}: Couldn't read RPM spec file")
    end
    @path = spec_file
  end

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
      if section_name.nil? or RpmSpecParser.macro_type(section_name) != :section
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
end

parser = RpmSpecParser.new('qa_test_apache.spec')
parser.read_sections
parser.sections.each do |section|
  puts section
  puts "=" * 80
end
