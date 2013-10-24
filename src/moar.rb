#!/usr/bin/ruby

require "curses"

class LineEditor
  include Curses

  attr_reader :string
  attr_reader :cursor_position

  def initialize
    @done = false
    @string = ''
    @cursor_position = 0
  end

  def enter_char(char)
    case char
    when 10  # 10=RETURN on a Powerbook
      @done = true
    when 127 # 127=BACKSPACE on a Powerbook
      @string = @string[0..-2]
      @cursor_position -= 1

      if @cursor_position < 0 && @string.empty?
        @done = true
      end
    else
      @string << char.chr
      @cursor_position += 1
    end
    @cursor_position = [@cursor_position, 0].min
    @cursor_position = [@cursor_position, @string.length].max
  end

  def done?
    return @done
  end
end

class Terminal
  include Curses

  def initialize
    init_screen
    noecho
    stdscr.keypad(true)
    crmode
  end

  def close
    close_screen
  end

  def lines
    super
  end

  def cols
    super
  end

  def attrset(attributes)
    super(attributes)
  end

  def addstr(string)
    super(string)
  end

  def setpos(line, col)
    super(line, col)
  end

  def clrtoeol
    super
  end

  def refresh
    super
  end

  def getch
    super
  end
end

class Moar
  def initialize(file)
    @terminal = Terminal.new
    @first_line = 0
    @lines = file.readlines
    @last_key = 0
    @done = false

    # Mode can be :viewing and :searching
    @mode = :viewing
  end

  def add_view_status
    status = "Lines #{@first_line + 1}-"

    status += "#{last_line + 1}"

    status += "/#{@lines.size}"

    percent_displayed =
      (100 * (last_line + 1) / @lines.size).floor
    status += " #{percent_displayed}%"
    status += ", last key=#{@last_key}"

    @terminal.attrset(Curses::A_REVERSE)
    @terminal.addstr(status)
  end

  def add_search_status
    status = "/#{@search_editor.string}"
    @terminal.addstr(status)
  end

  def add_line(screen_line, line)
    @terminal.attrset(Curses::A_NORMAL)
    @terminal.setpos(screen_line, 0)
    @terminal.clrtoeol

    # Higlight search matches
    remaining = line
    printed_chars = 0
    if @search_editor && @search_editor.string.length > 0
      while true
        (head, match, tail) = remaining.partition(@search_editor.string)
        if match.empty?
          break
        end
        remaining = tail

        @terminal.addstr(head)
        printed_chars += head.length
        @terminal.attrset(Curses::A_REVERSE)
        @terminal.addstr(match)
        printed_chars += match.length
        @terminal.attrset(Curses::A_NORMAL)

        if printed_chars > @terminal.cols
          break
        end
      end
    end

    # Print non-matching end of the line
    if printed_chars <= @terminal.cols
      @terminal.addstr(remaining)
      printed_chars += remaining.length
    end

    # Print a continuation character if we've printed outside the
    # window
    if printed_chars > @terminal.cols
      @terminal.setpos(screen_line, @terminal.cols - 1)
      @terminal.attrset(Curses::A_REVERSE)
      @terminal.addstr(">")
    end
  end

  def first_line
    # @first_line must not be closer than lines-2 from the end
    max_first_line = @lines.size - (@terminal.lines - 1)
    @first_line = [@first_line, max_first_line].min

    # @first_line cannot be negative
    @first_line = [0, @first_line].max

    return @first_line
  end

  # Compute the last line given a first line
  def last_line(my_first_line = nil)
    my_first_line = first_line unless my_first_line

    # my_first_line must not be closer than lines-2 from the end
    max_first_line = @lines.size - (@terminal.lines - 1)
    my_first_line = [my_first_line, max_first_line].min

    # my_first_line cannot be negative
    my_first_line = [0, my_first_line].max

    return_me = my_first_line + @terminal.lines - 2
    return_me = [@lines.size - 1, return_me].min

    return return_me
  end

  def last_line=(new_last_line)
    @first_line = new_last_line - @terminal.lines + 2
  end

  def draw_screen
    screen_line = 0

    # Draw lines
    (first_line..last_line).each do |line_number|
      add_line(screen_line, @lines[line_number].strip)
      screen_line += 1
    end

    # Draw filling after EOF
    if screen_line < (@terminal.lines - 1)
      @terminal.setpos(screen_line, 0)
      @terminal.clrtoeol
      @terminal.attrset(Curses::A_REVERSE)
      @terminal.addstr("---")
      screen_line += 1
    end

    while screen_line < (@terminal.lines - 1)
      @terminal.setpos(screen_line, 0)
      @terminal.clrtoeol
      screen_line += 1
    end

    # Draw status line
    @terminal.setpos(@terminal.lines - 1, 0)
    @terminal.clrtoeol
    case @mode
    when :viewing
      add_view_status
    when :searching
      add_search_status
    else
      abort("ERROR: Unsupported mode of operation <#{@mode}>")
    end

    @terminal.refresh
  end

  def handle_view_keypress(key)
    case key
    when ?q.ord
      @done = true
    when ?/.ord
      @mode = :searching
      @search_editor = LineEditor.new
    when ?n.ord
      full_search
    when ?N.ord
      full_search_backwards
    when Curses::Key::RESIZE
      # Do nothing; draw_screen() will be called anyway between all
      # keypresses
    when Curses::Key::DOWN
      @first_line += 1
    when Curses::Key::NPAGE, ' '[0]
      @first_line = last_line + 1
    when Curses::Key::PPAGE
      self.last_line = first_line - 1
    when ?<.ord
      @first_line = 0
    when ?>.ord
      @first_line = @lines.size
    when Curses::Key::UP
      @first_line -= 1
    end
  end

  # Get a certain line number on-screen
  def show_line(line_number)
    new_first_line = line_number

    # Move at least one screen away from where we were
    if new_first_line < first_line
      # Moving up
      if last_line(new_first_line) >= first_line
        self.last_line = first_line - 1
        return
      end
    end

    if new_first_line > last_line
      # Moving down
      new_first_line =
        [new_first_line, last_line + 1].max
    end

    @first_line = new_first_line
  end

  # Search the given line number ranges and scroll the view to show
  # the first match.
  #
  # Returns true if found and scrolled, false otherwise.
  def search_ranges(first_range, second_range)
    [first_range, second_range].each do |range|
      next unless range

      first = range.first
      last = range.last

      line_numbers = first.upto(last)
      if last < first
        line_numbers = first.downto(last)
      end

      line_numbers.each do |line_number|
        if @lines[line_number].index(@search_editor.string)
          show_line(line_number)
          return true
        end
      end
    end

    return false
  end

  # Search the full document and scroll to show the first hit
  def full_search
    return unless @search_editor
    return if @search_editor.string.empty?

    # Start searching from the first not-visible line after the
    # current screen
    first_not_visible = last_line + 1

    first_range = first_not_visible..(@lines.size - 1)
    first_range = nil unless first_not_visible <= (@lines.size - 1)

    # Wrap the search and search from the beginning until the last
    # not-visible line before the current screen
    last_not_visible = first_line - 1
    second_range = 0..last_not_visible
    second_range = nil unless last_not_visible >= 0

    search_ranges(first_range, second_range)
  end

  # Search the full document backwards and scroll to show the first
  # hit
  def full_search_backwards
    return unless @search_editor
    return if @search_editor.string.empty?

    # Start searching from the last non-visible line above the visible
    # screen
    last_not_visible = first_line - 1
    first_range = last_not_visible..0
    first_range = nil unless last_not_visible >= 0

    # Wrap the search and continue searching at the last line up to
    # the first not visible line below the current screen
    first_not_visible = last_line + 1
    second_range = (@lines.size - 1)..first_not_visible
    second_range = nil unless first_not_visible <= (@lines.size - 1)

    search_ranges(first_range, second_range)
  end

  def full_search_required?
    return false unless @search_editor
    return false if @search_editor.string.empty?

    @lines[first_line..last_line].each do |line|
      return false if line.index(@search_editor.string)
    end

    return true
  end

  def run
    begin
      while !@done
        draw_screen

        key = @terminal.getch
        case @mode
        when :viewing
          handle_view_keypress(key)
        when :searching
          @search_editor.enter_char(key)
          if full_search_required?
            full_search
          end
          if @search_editor.done?
            @mode = :viewing
          end
        else
          abort("ERROR: Unsupported mode of operation <#{@mode}>")
        end

        @last_key = key
      end
    ensure
      @terminal.close
    end
  end
end

if __FILE__ != $0
  # We're being required, probably due to unit testing.
  # Do nothing.
elsif $stdin.isatty
  File.open(ARGV[0], "r") do |file|
    Moar.new(file).run
  end
else
  # Switch around some fds to enable us to read the former stdin and
  # curses to read the "real" stdin.
  stream = $stdin.clone
  $stdin.reopen($stdout)
  Moar.new(stream).run
end
