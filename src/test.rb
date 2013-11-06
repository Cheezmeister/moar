#!/usr/bin/ruby

require 'pathname'
require 'test/unit'

require "#{Pathname(__FILE__).realpath.dirname}/moar.rb"

# Tests for the line editor
class TestLineEditor < Test::Unit::TestCase
  include Curses

  def assert_add(test_me, key, string, cursor_pos, done)
    test_me.enter_char(key)
    assert_equal(string, test_me.string, 'string')
    assert_equal(cursor_pos, test_me.cursor_position, 'cursor position')
    assert_equal(done, test_me.done?, 'done')

    if string.empty?
      assert(test_me.empty?)
    else
      assert(!test_me.empty?)
    end
  end

  def test_basic
    test_me = LineEditor.new
    assert_equal('', test_me.string)
    assert_equal(0, test_me.cursor_position)
    assert(!test_me.done?)

    assert_add(test_me, 'a'.ord, 'a', 1, false)
    assert_add(test_me, 'b'.ord, 'ab', 2, false)
    assert_add(test_me, 'c'.ord, 'abc', 3, false)

    # 127 = BACKSPACE on a Powerbook.  Key::BACKSPACE is something
    # else, don't know why they aren't one and the same.
    assert_add(test_me, 127, 'ab', 2, false)

    # 10 == RETURN on a Powerbook.  Key::ENTER is something else,
    # don't know why they aren't one and the same.
    assert_add(test_me, 10, 'ab', 2, true)
  end

  def test_out_of_range_char
    test_me = LineEditor.new
    assert_add(test_me, 42_462_124_635, '', 0, false)
  end

  # Verify that we become done after backspacing out of an empty
  # line
  def test_done_on_empty_backspace
    test_me = LineEditor.new
    assert_add(test_me, 127, '', 0, true)
  end

  def test_regexp
    # Only lower case chars => case insensitive regexp
    assert_equal(/apa/i, LineEditor.new('apa').regexp)

    # Valid regexp => regexp
    assert_equal(/[mos]/i, LineEditor.new('[mos]').regexp)

    # Invalid regexp => string search
    assert_equal(/\[mos/i, LineEditor.new('[mos').regexp)

    # One upper case char => case sensitive regexp
    assert_equal(/Apa/, LineEditor.new('Apa').regexp)
  end
end

# A mock terminal that doesn't actually display anything
class MockTerminal
  # We can display two lines
  def lines
    return 2
  end
end

# Tests for the pager logic
class TestMoar < Test::Unit::TestCase
  def test_line_methods
    # This method assumes the MockTerminal can display two lines
    terminal = MockTerminal.new
    test_me = Moar.new(%w(1 2 3 4), terminal)

    assert_equal(0, test_me.first_line)
    assert_equal(1, test_me.last_line)

    assert_equal(2, test_me.last_line(1))

    test_me.last_line = 2
    assert_equal(1, test_me.first_line)
    assert_equal(2, test_me.last_line)
  end

  def test_search_range
    terminal = MockTerminal.new
    test_me = Moar.new(%w(0 1 2 3 4), terminal)

    assert_equal(0, test_me.search_range(0, 4, '0'))
    assert(!test_me.search_range(1, 4, '0'))
    assert(!test_me.search_range(0, 3, '4'))
  end

  def test_search_range_with_ansi_escapes
    terminal = MockTerminal.new
    test_me = Moar.new(["#{27.chr}[mapa"], terminal)
    assert_equal(0, test_me.search_range(0, 0, 'apa'))
    assert_nil(test_me.search_range(0, 0, 'kalas'))
    assert_nil(test_me.search_range(0, 0, 'm'),
               "'m' is part of the escape code and should be ignored")
    assert_nil(test_me.search_range(0, 0, 'mapa'))
  end

  def test_full_search
    # This method assumes the MockTerminal can display two lines
    terminal = MockTerminal.new
    test_me = Moar.new(%w(0 1 2 3 4), terminal)

    assert_equal(2, test_me.full_search('2'))
    assert(!test_me.full_search('1'))
    assert_equal(2, test_me.full_search('2'))
  end

  def test_full_search_at_bottom
    # This method assumes the MockTerminal can display two lines
    terminal = MockTerminal.new
    test_me = Moar.new(%w(0 1), terminal)

    assert_equal(1, test_me.full_search('1'))
    assert_equal(1, test_me.full_search('1'))
  end
end

# Test our string-with-ANSI-control-codes class
class TestAnsiString < Test::Unit::TestCase
  ESC = 27.chr
  R = "#{ESC}[7m"  # REVERSE
  N = "#{ESC}[27m" # NORMAL

  def test_tokenize_empty
    count = 0
    AnsiString.new('').tokenize do |code, text|
      count += 1
      assert_equal(1, count)

      assert_equal(nil, code)
      assert_equal('', text)
    end
  end

  def test_tokenize_uncolored
    count = 0
    AnsiString.new('apa').tokenize do |code, text|
      count += 1
      assert_equal(1, count)

      assert_equal(nil, code)
      assert_equal('apa', text)
    end
  end

  def test_tokenize_color_at_start
    tokens = []
    AnsiString.new("#{ESC}[31mapa").tokenize do |code, text|
      tokens << [code, text]
    end

    assert_equal([%w(31m apa)], tokens)
  end

  def test_tokenize_color_middle
    tokens = []
    AnsiString.new("flaska#{ESC}[1mapa").tokenize do |code, text|
      tokens << [code, text]
    end

    assert_equal([[nil, 'flaska'],
                  %w(1m apa)], tokens)
  end

  def test_tokenize_color_end
    tokens = []
    AnsiString.new("flaska#{ESC}[m").tokenize do |code, text|
      tokens << [code, text]
    end

    assert_equal([[nil, 'flaska'], ['m', '']], tokens)
  end

  def test_tokenize_color_many
    tokens = []
    string = AnsiString.new("#{ESC}[1mapa#{ESC}[2mgris#{ESC}[3m")
    string.tokenize do |code, text|
      tokens << [code, text]
    end

    assert_equal([%w(1m apa),
                  %w(2m gris),
                  ['3m', '']], tokens)
  end

  def test_tokenize_consecutive_colors
    tokens = []
    AnsiString.new("apa#{ESC}[1m#{ESC}[2mgris").tokenize do |code, text|
      tokens << [code, text]
    end

    assert_equal([[nil, 'apa'], ['1m', ''], %w(2m gris)], tokens)
  end

  def highlight(base, search_term)
    return AnsiString.new(base).highlight(search_term).to_str
  end

  def test_highlight_nothing
    assert_equal('1234', highlight('1234', '5'))

    string = "#{ESC}1mapa#{ESC}2mgris#{ESC}3m"
    assert_equal(string, highlight(string, 'aardvark'))
  end

  def test_highlight_undecorated
    assert_equal("a#{R}p#{N}a",
                 highlight('apa', 'p'))
    assert_equal("#{R}ap#{N}a",
                 highlight('apa', 'ap'))
    assert_equal("a#{R}pa#{N}",
                 highlight('apa', 'pa'))
    assert_equal("#{R}apa#{N}",
                 highlight('apa', 'apa'))

    assert_equal("#{R}a#{N}p#{R}a#{N}",
                 highlight('apa', 'a'))
  end

  def test_highlight_decorated
    string = "apa#{ESC}[31mgris#{ESC}[32morm"

    assert_equal("#{R}apa#{N}#{ESC}[31mgris#{ESC}[32morm",
                 highlight(string, 'apa'))
    assert_equal("apa#{ESC}[31m#{R}gris#{N}#{ESC}[32morm",
                 highlight(string, 'gris'))
    assert_equal("apa#{ESC}[31mgris#{ESC}[32m#{R}orm#{N}",
                 highlight(string, 'orm'))

    assert_equal("apa#{ESC}[31mg#{R}r#{N}is#{ESC}[32mo#{R}r#{N}m",
                 highlight(string, 'r'))
  end

  def test_dont_highlight_ansi_codes
    string = "3#{ESC}[3m3"

    assert_equal("#{R}3#{N}#{ESC}[3m#{R}3#{N}",
                 highlight(string, '3'))
  end

  def test_include?
    test_me = AnsiString.new("#{27.chr}[mapa")
    assert(test_me.include?('apa'))
    assert(!test_me.include?('m'),
           "'m' is part of the escape code and should be ignored")
    assert(!test_me.include?('mapa'))
  end

  def test_plain_substring
    assert_equal('', AnsiString.new('').substring(0).to_str)
    assert_equal('', AnsiString.new('').substring(5).to_str)

    assert_equal('01234', AnsiString.new('01234').substring(0).to_str)
    assert_equal('234', AnsiString.new('01234').substring(2).to_str)
    assert_equal('', AnsiString.new('01234').substring(5).to_str)
  end

  def test_ansi_substring
    test_me =
      AnsiString.new("#{ESC}[33m012#{ESC}[34m345#{ESC}[35m678")

    assert_equal("#{ESC}[33m012#{ESC}[34m345#{ESC}[35m678",
                 test_me.substring(0).to_str)
    assert_equal("#{ESC}[33m12#{ESC}[34m345#{ESC}[35m678",
                 test_me.substring(1).to_str)
    assert_equal("#{ESC}[33m2#{ESC}[34m345#{ESC}[35m678",
                 test_me.substring(2).to_str)
    assert_equal("#{ESC}[33m#{ESC}[34m345#{ESC}[35m678",
                 test_me.substring(3).to_str)
    assert_equal("#{ESC}[33m#{ESC}[34m45#{ESC}[35m678",
                 test_me.substring(4).to_str)
    assert_equal("#{ESC}[33m#{ESC}[34m5#{ESC}[35m678",
                 test_me.substring(5).to_str)
    assert_equal("#{ESC}[33m#{ESC}[34m#{ESC}[35m678",
                 test_me.substring(6).to_str)
    assert_equal("#{ESC}[33m#{ESC}[34m#{ESC}[35m78",
                 test_me.substring(7).to_str)
    assert_equal("#{ESC}[33m#{ESC}[34m#{ESC}[35m8",
                 test_me.substring(8).to_str)
    assert_equal("#{ESC}[33m#{ESC}[34m#{ESC}[35m",
                 test_me.substring(9).to_str)
    assert_equal("#{ESC}[33m#{ESC}[34m#{ESC}[35m",
                 test_me.substring(10).to_str)
  end
end
