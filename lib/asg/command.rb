require 'fileutils'
require 'digest/sha1'
require 'zlib'
require 'find'
require 'set'
require 'pathname'

module Asg
  class Command
    GIT_DIR = ".asg"
    GIT_IGNORE = ".asg_ignore"
    BASE_PATH_START = GIT_DIR.size + 1
    OBJ_DIR = File.join(GIT_DIR, "objects")
    HEAD_FILE = File.join(GIT_DIR, "HEAD")
    MERGE_HEAD_FILE = File.join(GIT_DIR, "MERGE_HEAD")
    INDEX_FILE = File.join(GIT_DIR, "index")
    REF_DIR = File.join(GIT_DIR, "refs")
    TAG_DIR = File.join(REF_DIR,"tags")
    HEADS_DIR = File.join(REF_DIR, "heads")
    BASE_HEADS_DIR = HEADS_DIR[BASE_PATH_START..-1]
    BASE_TAG_DIR = TAG_DIR[BASE_PATH_START..-1]
    BLOB_TYPE = "blob"
    TREE_TYPE = "tree"
    COMMIT_TYPE = "commit"

    class << self
      def init
        FileUtils.mkdir_p([GIT_DIR, OBJ_DIR, TAG_DIR, REF_DIR, HEADS_DIR])
        FileUtils.touch(HEAD_FILE)
        set_head branch_ref_val("master")
        puts "Initialized empty Git repository in #{Dir.pwd}/#{GIT_DIR}/"
      end

      def hash_object(file_content, type="blob")
        data = "#{type}\0#{file_content}"
        sha = Digest::SHA1.hexdigest(data)
        obj = Zlib::Deflate.deflate(data)
        File.write(File.join(OBJ_DIR, sha), obj)
        sha
      end

      def get_object(obj_id)
        data = IO.binread(File.join(OBJ_DIR, obj_id))
        _, content = Zlib::Inflate.inflate(data).split("\0")
        content || ""
      end

      def write_index_tree(tree_hash)
        objects = []
        tree_hash.each do |entry, entry_value|
          if entry_value.is_a?(Hash)
            object_type = TREE_TYPE
            object_id = write_index_tree(entry_value)
          else
            object_type = BLOB_TYPE
            object_id = entry_value
          end
          objects << [entry, object_id, object_type]
        end
        tree_content = objects.sort.map{|obj| "#{obj[2]} #{obj[1]} #{obj[0]}\n"}.join
        hash_object(tree_content, TREE_TYPE)
      end

      def write_tree
        write_index_tree(get_index_tree)
      end

      def write_directory_tree(directory=".")
        objects = []
        Dir.foreach(directory) do |entry|
          next if Ignore.matched?(entry) || entry == "." || entry == ".."
          path = File.join(directory, entry)
          if File.directory?(path)
            object_type = TREE_TYPE
            object_id = write_directory_tree(path)
          else
            object_type = BLOB_TYPE
            object_id = hash_object(File.read(path))
          end

          objects << [entry, object_id, object_type]
        end
        tree_content = objects.sort.map{|obj| "#{obj[2]} #{obj[1]} #{obj[0]}\n"}.join
        hash_object(tree_content, TREE_TYPE)
      end

      def get_tree(object_id, directory = ".")
        return {} if object_id.nil? || object_id.empty?
        path_oid_hash = {}
        get_object(object_id).split("\n").map{|line|line.split(" ")}.each do |obj_type, obj_id, obj_name|
          path = directory == "." ? obj_name : File.join(directory, obj_name)
          if obj_type == BLOB_TYPE
            path_oid_hash[path] = obj_id
          elsif obj_type == TREE_TYPE
            path_oid_hash.merge!(get_tree(obj_id, path))
          else
            raise "Unknown object type: #{obj_type}"
          end
        end
        path_oid_hash
      end

      def get_working_tree
        path_oid_hash = {}
        Find.find(".").each do |path|
          next if path == "." || !File.file?(path)
          path = path[2..-1]
          Find.prune if Ignore.matched?(path)
          path_oid_hash[path] = hash_object(File.read(path))
        end
        path_oid_hash
      end

      def read_tree(tree_oid, update_directory=false)
        get_index do |index|
          index.clear
          index.merge! get_tree(tree_oid)
          if update_directory
            checkout_index index
          end
        end
      end

      def checkout_index(index=nil)
        clear_all
        (index || get_index).each do |path, oid|
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, get_object(oid))
        end
      end

      def read_tree_in_working_directory(object_id)
        clear_all
        get_tree(object_id).each do |path, oid|
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, get_object(oid))
        end
      end

      def clear_all(directory = ".")
        dirs = []
        Find.find(directory).each do |path|
          next if path == "."
          Find.prune if Ignore.matched?(path[2..-1])

          if File.directory?(path)
            dirs << path
            next
          end

          FileUtils.rm(path) if File.file?(path)
        end

        dirs.reverse.each do |dir|
          Dir.rmdir(dir) rescue SystemCallError
        end
      end

      def commit(message)
        content = "tree #{write_tree}\n"
        head_oid = get_head
        if head_oid
          content += "parent #{head_oid}\n"
        end

        merge_head = get_ref(MERGE_HEAD_FILE).value
        if merge_head
          content += "parent #{merge_head}\n"
          delete_ref(MERGE_HEAD_FILE, false)
        end

        content += "\n#{message}\n"
        oid = hash_object(content, COMMIT_TYPE)
        set_head oid
        oid
      end

      def set_head(ref_value, follow_link=true)
        real_path = follow_link ? _get_ref_with_path(HEAD_FILE).last : HEAD_FILE
        File.write(real_path, ref_value)
      end

      def get_head
        get_ref(HEAD_FILE)&.value
      end

      def set_ref(ref_file, ref_obj, follow_link=true)
        ref_file = _get_ref_with_path(ref_file, follow_link).last
        ref_value = ref_obj.is_linked ? "ref: #{ref_obj.value}" : ref_obj.value
        ref_dir = File.dirname(ref_file)
        FileUtils.mkdir_p(ref_dir) unless Dir.exist?(ref_dir)
        File.write(ref_file, ref_value)
      end

      def delete_ref(ref, follow_link=true)
        ref = _get_ref_with_path(ref, follow_link).last
        FileUtils.rm ref
      end

      def abs_ref_path(ref)
        ref.start_with?(GIT_DIR) ? ref : File.join(GIT_DIR, ref)
      end

      def get_ref(ref, follow_link=true)
        _get_ref_with_path(ref, follow_link).first
      end

      def _get_ref_with_path(ref, follow_link=true)
        ref_file = abs_ref_path(ref)
        oid = nil
        if File.exist?(ref_file)
          oid = File.read(ref_file)
        end

        if oid&.start_with?("ref:")
          if follow_link
            return _get_ref_with_path(oid[4..-1].strip)
          else
            return [Structure::Reference.new(oid[4..-1].strip, true), ref_file]
          end
        end

        [Structure::Reference.new(oid, false), ref_file]
      end

      def get_commit(oid)
        commit = Structure::Commit.new(nil, [], "")
        commit_lines = get_object(oid).split("\n")
        commit_lines.each_with_index do |line, i|
          if line.empty?
            commit.message = commit_lines[i+1..-1].join("\n")
            break
          else
            line_type, line_item = line.split(" ")
            if line_type == TREE_TYPE
              commit.tree = line_item
            elsif line_type == "parent"
              commit.parents << line_item
            end
          end
        end
        commit
      end

      def log(oid=nil)
        oid_refs = Hash.new{|h, k| h[k] = []}
        enum_refs do |ref, ref_oid|
          oid_refs[ref_oid] << ref
        end

        enum_commits([oid || get_head]) do |oid_, commit|
          _print_commit(oid_, commit, oid_refs[oid_])
        end
      end

      def _print_commit(oid, commit_obj, commit_refs=[])
        refs = commit_refs.empty? ? "" : " (" + commit_refs.join(", ") + ")"
        puts "commit #{oid}#{refs}"
        puts "    #{commit_obj.message}"
      end

      def is_branch?(name)
        !get_ref(File.join(HEADS_DIR, name)).value.nil?
      end

      def checkout(name)
        oid = get_oid name
        if get_head != oid
          commit = get_commit oid
          read_tree(commit.tree, true)
        end

        is_valid_branch = is_branch?(name)
        ref_val = is_valid_branch ? branch_ref_val(name) : oid
        set_head(ref_val, false)

        if is_valid_branch
          puts "Switched to branch '#{name}'"
        else
          puts "HEAD is now at #{oid}"
        end
      end

      def tag(name, commit_oid = nil)
        commit_oid ||= get_head
        set_ref(File.join(TAG_DIR, name), Structure::Reference.new(commit_oid))
      end

      def branch_ref_val(name)
        "ref: #{File.join(BASE_HEADS_DIR, name)}"
      end

      def get_oid(name)
        return name if File.exist?(File.join(OBJ_DIR, name))
        [
          File.join(HEADS_DIR, name),
          File.join(TAG_DIR, name),
          File.join(REF_DIR, name),
          File.join(GIT_DIR, name)
        ].each {|f| return File.read(f) if File.exist?(f)}
        nil
      end

      def enum_branches
        enum_refs(BASE_HEADS_DIR) do |ref, _|
          yield ref[BASE_HEADS_DIR.size+1..-1]
        end
      end

      def enum_refs(ref_prefix=nil)
        refs = ["HEAD", "MERGE_HEAD"]
        Find.find(REF_DIR).each do |path|
          if File.file?(path)
            refs << path[BASE_PATH_START..-1]
          end
        end

        refs.each do |ref|
          if ref_prefix.nil? || ref.start_with?(ref_prefix)
            ref_value = get_ref(ref, false).value
            yield(ref, ref_value) unless ref_value.nil?
          end
        end
      end

      def enum_commits(oid_list)
        visited = Set.new
        while oid_list.size > 0
          oid = oid_list.pop
          next if oid.nil? || visited.include?(oid)
          visited.add oid
          commit = get_commit oid
          yield oid, commit
          oid_list += commit.parents.reverse
        end
      end

      def branch(name, ref)
        oid = get_oid ref
        raise "Not a valid object name: '#{ref}'." if oid.nil?
        fp = File.join(HEADS_DIR, name)
        raise "A branch named '#{name}' already exists." if File.exist? fp
        set_ref(fp, Structure::Reference.new(oid))
      end

      def branch_name
        head = get_ref(HEAD_FILE, false)
        if head.is_linked && head.value
          head.value[BASE_HEADS_DIR.size+1..-1]
        end
      end

      def reset(oid)
        set_head oid
      end

      def show(commit_oid)
        $stdout = StringIO.new
        begin
          commit = get_commit commit_oid
          _print_commit(commit_oid, commit)

          old_tree_id = commit.parents.empty? ? nil : get_commit(commit.parents[0]).tree
          changed_files, diffs = Diff.diff_trees(get_tree(commit.tree), get_tree(old_tree_id))

          changed_files.each do |status, files|
            next if files.empty?
            puts "#{status.upcase}: "
            files.each{|f| puts "    #{f}"}
          end
          puts diffs.join("\n")

          Open3.pipeline(["echo", $stdout.string], ["more", "-d"])
        ensure
          $stdout = STDOUT
        end
      end

      def diff(opts={})
        commit = get_commit opts[:oid]
        if opts[:cached]
          diffs = Diff.diff_trees(get_index, get_tree(commit.tree)).last
        else
          diffs = Diff.diff_trees(get_working_tree, get_index).last
        end
        Open3.pipeline(["echo", diffs.join("\n")], ["more", "-d"])
      end

      def status
        branch = branch_name
        head_commit = get_head
        if branch
          puts "On branch #{branch}"
        else
          puts "HEAD detached at #{head_commit}"
        end

        if head_commit.nil?
          puts "\nNo commits yet"
        end

        merge_head = get_ref(MERGE_HEAD_FILE).value
        if merge_head
          puts "Merging with #{merge_head}"
        end

        index_tree = get_index
        head_tree = head_commit ? get_tree(get_commit(head_commit).tree) : {}
        files_to_commit = Diff.diff_trees(index_tree, head_tree, false).first
        can_commit = !files_to_commit.all? {|_, v| v.empty?}
        if can_commit
          puts "\nChanges to be committed:"
          puts
          files_to_commit.each do |status, files|
            next if files.empty?
            files.each{|f| puts "    #{status.downcase}:  #{f}"}
          end
        end

        working_tree = get_working_tree
        files_to_stage = Diff.diff_trees(working_tree, index_tree, false).first
        new_files = files_to_stage.delete(:"new file")
        if files_to_stage.all? {|_, v| v.empty?}
          if !can_commit && new_files.empty?
            if working_tree.empty?
              puts "nothing to commit (create/copy files and use \"asg add\" to track)"
            else
              puts "nothing to commit, working tree clean"
            end
          end
        else
          puts "\nChanges not staged for commit:"
          puts
          files_to_stage.each do |status, files|
            next if files.empty?
            files.each{|f| puts "    #{status.downcase}:  #{f}"}
          end
        end

        unless new_files.empty?
          puts "\nUntracked files:"
          puts "  (use \"asg add <file>...\" to include in what will be committed)"
          puts
          new_files.each{|f| puts "    #{f}"}
          unless can_commit
            puts "\nnothing added to commit but untracked files present (use \"asg add\" to track)"
          end
          puts
        end
      end

      def read_tree_with_merge(base_tree_oid, head_tree_oid, other_tree_oid, update_directory=false)
        get_index do |index|
          index.clear
          hs = Diff.merge_trees(get_tree(base_tree_oid), get_tree(head_tree_oid), get_tree(other_tree_oid))
          index.merge!(hs)
          if update_directory
            checkout_index index
          end
        end
      end

      def merge(ref_or_oid)
        head_oid = get_head
        return if head_oid.nil?
        commit_oid = get_oid ref_or_oid
        base_oid = merge_base(head_oid, commit_oid)
        other_commit = get_commit(commit_oid)

        if base_oid == head_oid
          read_tree(other_commit.tree, true)
          set_head commit_oid
          puts "fast-forward merged"
          return
        end

        set_ref(MERGE_HEAD_FILE, Structure::Reference.new(commit_oid))
        read_tree_with_merge(get_commit(base_oid).tree, get_commit(head_oid).tree, other_commit.tree, true)
        puts "please commit"
      end

      def merge_base(oid1, oid2)
        oid1_parents = Set.new
        enum_commits([oid1]) do |oid, _|
          oid1_parents << oid
        end

        enum_commits([oid2]) do |oid, _|
          return oid if oid1_parents.include?(oid)
        end
      end

      def get_index
        index = {}
        if File.exist?(INDEX_FILE)
          content = File.read(INDEX_FILE)
          index = Marshal.load content
        end
        if block_given?
          yield index
          File.write(INDEX_FILE, Marshal.dump(index))
        end
        index
      end

      def get_index_tree
        hs = {}
        get_index.each do |path, oid|
          path_parts = path.split("/")
          file_name = path_parts.pop
          current = hs
          path_parts.each do |dir|
            current = (current[dir] ||= {})
          end
          current[file_name] = oid
        end
        hs
      end

      def add(files)
        total_files = Set.new
        ignored_files = Set.new
        dir_path = Dir.pwd

        files.map do |f|
          raise "pathspec '#{f}' did not match any files" unless File.exist?(f)
          abs_path = File.expand_path f
          raise "#{File.expand_path(f)} is outside repository" unless abs_path.start_with?(dir_path)
          abs_path == dir_path ? "." : abs_path.sub("#{dir_path}/","")
        end.each do |f|
          if File.directory?(f)
            Find.find(f).each do |path|
              next if path == "."
              fp = f == "." ? path[2..-1] : path
              if Ignore.matched?(fp) || (File.directory?(fp) && Ignore.matched?(File.join(fp, "/")))
                ignored_files << fp
                Find.prune
              end
              total_files << fp if File.file?(fp)
            end
          else
            total_files << f
          end
        end

        unless total_files.empty?
          get_index do |index|
            total_files.each do |f|
              index[f] = hash_object(File.read(f))
            end
          end
        end

        if !ignored_files.empty? && !files.include?(".")
          puts "The following paths are ignored by your #{GIT_IGNORE} file:"
          puts ignored_files.to_a
        end
      end
    end
  end
end
