$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
require "rbs"
require "tmpdir"
require 'minitest/reporters'
require "stringio"
require "open3"

Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new]

RBS.logger.level = Logger::INFO

if ENV["RUNTIME_TEST"]
  require "rbs/test"

  sample_size = case size = (ENV["RUNTIME_TEST_SAMPLE_SIZE"] || "2")
                when "ALL"
                  nil
                else
                  size.to_i
                end

  loader = RBS::EnvironmentLoader.new
  loader.add(path: Pathname(__dir__)+"../sig")
  loader.add(library: "set")

  env = RBS::Environment.from_loader(loader).resolve_type_names
  tester = RBS::Test::Tester.new(env: env)

  test_classes = []
  test_classes << RBS::Buffer
  test_classes << RBS::Location
  # test_classes << RBS::Namespace
  # test_classes << RBS::TypeName
  test_classes << RBS::Types::NoFreeVariables
  test_classes << RBS::Types::NoSubst
  test_classes << RBS::Types::NoTypeName
  test_classes << RBS::Types::EmptyEachType
  test_classes << RBS::Types::Bases::Base
  test_classes << RBS::Types::Bases::Bool
  test_classes << RBS::Types::Bases::Void
  test_classes << RBS::Types::Bases::Any
  test_classes << RBS::Types::Bases::Nil
  test_classes << RBS::Types::Bases::Top
  test_classes << RBS::Types::Bases::Bottom
  test_classes << RBS::Types::Bases::Self
  test_classes << RBS::Types::Bases::Instance
  test_classes << RBS::Types::Bases::Class

  test_classes.each do |klass|
    tester.install!(klass, sample_size: sample_size)
  end
end

module TestHelper
  def parse_type(string, variables: Set.new)
    RBS::Parser.parse_type(string, variables: variables)
  end

  def parse_method_type(string, variables: Set.new)
    RBS::Parser.parse_method_type(string, variables: variables)
  end

  def type_name(string)
    RBS::Namespace.parse(string).yield_self do |namespace|
      last = namespace.path.last
      RBS::TypeName.new(name: last, namespace: namespace.parent)
    end
  end

  def silence_errors
    RBS.logger.stub :error, nil do
      yield
    end
  end

  def silence_warnings
    RBS.logger.stub :warn, nil do
      yield
    end
  end

  class SignatureManager
    attr_reader :files
    attr_reader :system_builtin

    def initialize(system_builtin: false)
      @files = {}
      @system_builtin = system_builtin

      files[Pathname("builtin.rbs")] = BUILTINS unless system_builtin
    end

    def self.new(**kw)
      instance = super(**kw)

      if block_given?
        yield instance
      else
        instance
      end
    end

    BUILTINS = <<SIG
class BasicObject
  def __id__: -> Integer

  private
  def initialize: -> void
end

class Object < BasicObject
  include Kernel

  public
  def __id__: -> Integer

  private
  def respond_to_missing?: (Symbol, bool) -> bool
end

module Kernel
  private
  def puts: (*untyped) -> nil
  def to_i: -> Integer
end

class Class < Module
end

class Module
end

class String
  include Comparable

  def self.try_convert: (untyped) -> String?
end

class Integer
end

class Symbol
end

module Comparable
end

module Enumerable[A, B]
end
SIG

    def add_file(path, content)
      files[Pathname(path)] = content
    end

    def build
      Dir.mktmpdir do |tmpdir|
        tmppath = Pathname(tmpdir)

        files.each do |path, content|
          absolute_path = tmppath + path
          absolute_path.parent.mkpath
          absolute_path.write(content)
        end

        loader = RBS::EnvironmentLoader.new()
        loader.no_builtin! unless system_builtin
        loader.add path: tmppath

        yield RBS::Environment.from_loader(loader).resolve_type_names, tmppath
      end
    end
  end

  def assert_write(decls, string)
    writer = RBS::Writer.new(out: StringIO.new)
    writer.write(decls)

    assert_equal string, writer.out.string

    # Check syntax error
    RBS::Parser.parse_signature(writer.out.string)
  end

  def assert_sampling_check(builder, sample_size, array)
    checker = RBS::Test::TypeCheck.new(self_class: Integer, builder: builder, sample_size: sample_size)
    
    sample = checker.each_sample(array).to_a
    
    assert_operator(sample.size, :<=, array.size)
    assert_operator(sample.size, :<=, sample_size) unless sample_size.nil?
    assert_empty(sample - array)
  end
end

require "minitest/autorun"
