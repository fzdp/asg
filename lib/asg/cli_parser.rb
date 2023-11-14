require 'optparse'

module Asg
  class CliParser
    def self.parse
      cmd_opts = {}

      main_parser = OptionParser.new("asg") do |opts|
        opts.on("-h", "--help", "Print help") { puts "A Simple Git built by Ruby" }
      end

      init_parser = OptionParser.new("init") do |opts|
        opts.on do
          Command.init
        end
      end

      cat_file_parser = OptionParser.new("cat-file") do |opts|
        opts.on do
          data = Command.get_object(ARGV.last)
          print data
        end
      end

      hash_object_parser = OptionParser.new("hash-object") do |opts|
        opts.on do
          Command.hash_object(File.read(ARGV.last))
        end
      end

      write_tree_parser = OptionParser.new("write-tree") do |opts|
        opts.on do
          object_id = Command.write_tree
          puts object_id
        end
      end

      read_tree_parser = OptionParser.new("read-tree") do |opts|
        opts.on do
          object_id = ARGV.last
          Command.read_tree(object_id)
        end
      end

      commit_parser = OptionParser.new("commit") do |opts|
        opts.on("-m", "--message MESSAGE", "commit message") do |opt|
          cmd_opts[:message] = opt
        end

        opts.on do
          if cmd_opts[:message].nil?
            raise OptionParser::MissingArgument, "message required"
          end
          oid = Command.commit(cmd_opts[:message])
          puts oid
        end
      end

      log_parser = OptionParser.new("log") do |opts|
        opts.on(/.*/) do |ref|
          cmd_opts[:commit_oid] = get_oid ref
        end

        opts.on do
          Command.log cmd_opts[:commit_oid]
        end
      end

      checkout_parser = OptionParser.new("checkout") do |opts|
        opts.on(/.*/) do |ref|
          cmd_opts[:commit] = ref
        end

        opts.on do
          if cmd_opts[:commit].nil?
            raise OptionParser::MissingArgument, "commit required"
          end
          Command.checkout cmd_opts[:commit]
        end
      end

      tag_parser = OptionParser.new("tag") do |opts|
        opts.on do
          tag_name = ARGV.first
          commit_oid = ARGV.size == 2 ? ARGV.last : nil
          Command.tag(tag_name, commit_oid)
        end
      end

      branch_parser = OptionParser.new("branch") do |opts|
        opts.on do
          if ARGV.size == 0
            current_branch = Command.branch_name
            Command.enum_branches do |br|
              if br == current_branch
                puts "* #{br}"
              else
                puts "  #{br}"
              end
            end
          else
            oid = ARGV.size == 1 ? Command.branch_name : ARGV.last
            Command.branch ARGV.first, oid
          end
        end
      end

      status_parser = OptionParser.new("status") do |opts|
        opts.on do
          Command.status
        end
      end

      reset_parser = OptionParser.new("reset") do |opts|
        opts.on(/.*/) do |oid|
          cmd_opts[:oid] = oid
        end

        opts.on do
          if cmd_opts[:oid].nil?
            raise OptionParser::MissingArgument, "commit required"
          end
          Command.reset cmd_opts[:oid]
        end
      end

      show_parser = OptionParser.new("show") do |opts|
        opts.on(/.*/) do |oid|
          cmd_opts[:oid] = oid
        end

        opts.on do
          cmd_opts[:oid] ||= get_head
          Command.show cmd_opts[:oid]
        end
      end

      diff_parser = OptionParser.new("diff") do |opts|
        opts.on("--cached", "diff with head") do |_|
          cmd_opts[:cached] = true
        end

        opts.on(/.*/) do |oid|
          cmd_opts[:oid] = oid
        end

        opts.on do
          cmd_opts[:oid] ||= get_head
          Command.diff cmd_opts
        end
      end

      merge_parser = OptionParser.new("merge") do |opts|
        opts.on(/.*/) do |oid|
          cmd_opts[:oid] = oid
        end

        opts.on do
          Command.merge cmd_opts[:oid]
        end
      end

      merge_base_parser = OptionParser.new("merge-base") do |opts|
        opts.on do
          oid1 = ARGV.first
          oid2 = ARGV.last
          puts Command.merge_base(oid1, oid2)
        end
      end

      add_parser = OptionParser.new("add") do |opts|
        opts.on do
          if ARGV.size == 0
            puts "no files provided, nothing added."
            return
          end
          Command.add ARGV
        end
      end

      cmd_parser = {
        "init" => init_parser,
        "cat-file" => cat_file_parser,
        "hash-object" => hash_object_parser,
        "write-tree" => write_tree_parser,
        "read-tree" => read_tree_parser,
        "commit" => commit_parser,
        "log" => log_parser,
        "checkout" => checkout_parser,
        "tag" => tag_parser,
        "branch" => branch_parser,
        "status" => status_parser,
        "reset" => reset_parser,
        "show" => show_parser,
        "diff" => diff_parser,
        "merge" => merge_parser,
        "merge-base" => merge_base_parser,
        "add" => add_parser
      }

      begin
        cmd = ARGV.shift
        if cmd.nil? || %w[-h --help].include?(cmd)
          puts main_parser
          cmd_parser.values.each {|c| puts c}
        elsif cmd.start_with?("-")
          main_parser.parse ARGV
        else
          if cmd_parser.has_key?(cmd)
            if (cmd != "init") && !File.exist?(Command::GIT_DIR)
              raise "Not a git repository: #{Command::GIT_DIR}"
            end
            cmd_parser[cmd].parse ARGV
          else
            puts "asg: '#{cmd}' is not a git command. See 'asg --help'."
          end
        end
      rescue OptionParser::ParseError => e
        puts e.message
      rescue => e
        puts "fatal: #{e.message}"
      end
    end
  end
end