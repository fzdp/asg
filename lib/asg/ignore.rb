module Asg
  class Ignore
    class << self
      def match_patterns
        @_patterns ||= begin
          patterns = { ".asg" => true, ".asg/**" => true }
          if File.exist?(Command::GIT_IGNORE)
            File.readlines(Command::GIT_IGNORE, chomp: true).each do |line|
              next if line.empty? || line[0] == "#" || line[0] == " "
              line = line.strip
              if line[0] == "!"
                patterns[line[1..-1]] = false
              elsif line[0] == "\\"
                patterns[line[1..-1]] = true
              else
                patterns[line] = true
                if /\*|\?/ =~ line
                  next
                elsif line.end_with?("/")
                  patterns["#{line}**"] = true
                else
                  patterns["#{line}/**"] = true
                end
              end
            end
          end
          patterns
        end
      end

      def matched?(path)
        ignored = false
        match_patterns.each do |pn, is_ignored|
          ignored = is_ignored if File.fnmatch(pn, path, File::FNM_EXTGLOB | File::FNM_CASEFOLD)
        end
        ignored
      end
    end
  end
end