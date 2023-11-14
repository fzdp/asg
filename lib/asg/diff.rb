require 'tempfile'
require 'open3'

module Asg
  class Diff
    class << self
      def diff_trees(tree_path_hash_new, tree_path_hash_old, use_diff=true)
        changed_files = { "new file": [], deleted: [], modified: [] }
        diffs = []
        enum_trees(tree_path_hash_new, tree_path_hash_old) do |path, oid_new, oid_old|
          if oid_new != oid_old
            if oid_new && oid_old
              changed_files[:modified] << path
              diffs << diff_blobs(oid_new, oid_old, path) if use_diff
            elsif oid_old.nil?
              changed_files[:"new file"] << path
            else
              changed_files[:deleted] << path
            end
          end
        end
        [changed_files, diffs]
      end

      def diff_blobs(blob_new, blob_old, file_path)
        file_new = Tempfile.new(blob_new)
        file_old = Tempfile.new(blob_old)

        begin
          [[file_new, blob_new], [file_old, blob_old]].each do |f, b|
            f.write Command::get_object(b)
            f.rewind
          end
          o, _, _ = Open3.capture3("diff", "-u", "--label", "a/#{file_path}", file_old.path, "--label", "b/#{file_path}", file_new.path)
          o
        ensure
          [file_new, file_old].each do |f|
            f.close
            f.unlink
          end
        end
      end

      def merge_blobs(oid_base, oid_head, oid_other)
        file_base = Tempfile.new
        file_head = Tempfile.new
        file_other = Tempfile.new

        begin
          [[file_base, oid_base], [file_head, oid_head], [file_other, oid_other]].each do |f, oid|
            f.write Command::get_object oid if oid
            f.rewind
          end
          o, _, _ = Open3.capture3("diff3", "-m", "-L", "HEAD", file_head.path, "-L", "BASE", file_base.path, "-L", "MERGE_HEAD", file_other.path)
          o
        ensure
          [file_base, file_head, file_other].each do |f|
            f.close
            f.unlink
          end
        end
      end

      def enum_trees(*trees)
        tree_count = trees.size
        path_oid_list_hash = Hash.new{|h, k| h[k] = [nil] * tree_count}
        trees.each_with_index do |t, i|
          t.each do |path, oid|
            path_oid_list_hash[path][i] = oid
          end
        end

        path_oid_list_hash.each do |path, oid_list|
          yield path, *oid_list
        end
      end

      def merge_trees(tree_hash_base, tree_hash_head, tree_hash_other)
        path_merged_blobs = {}
        enum_trees(tree_hash_base, tree_hash_head, tree_hash_other) do |path, oid_base, oid_head, oid_other|
          path_merged_blobs[path] = Command::hash_object merge_blobs(oid_base, oid_head, oid_other)
        end
        path_merged_blobs
      end
    end
  end
end