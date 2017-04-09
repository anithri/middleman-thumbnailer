require 'middleman-thumbnailer/thumbnails'
require 'middleman-thumbnailer/helpers'
require 'middleman-thumbnailer/rack'

module Middleman
  module Thumbnailer
    class Extension < Middleman::Extension
      helpers Helpers

      option :dimensions
      option :namespace_directory, ['**']
      option :blog, true
      option :filetypes, [:jpg, :jpeg, :png]
      option :include_data_thumbnails, false
      option :images_source_dir
      option :source_dir
      option :root

      def initialize(app, options_hash = {}, &block)
        super
        @@options = options
      end

      def after_configuration
        # stash the source images dir in options for the Rack middleware
        options[:images_source_dir] = File.join(app.source_dir, app.images_dir)
        options[:source_dir] = app.source_dir
        options[:root] = app.root
        app.use Rack, options
      end

      def directories
        included_directories.map { |dir| path_for(dir) }
      end

      def included_directories
        dirs = [namespaced_images_directory]
        dirs << 'blog' if options[:blog]
      end

      def manipulate_resource_list(resources)
        thumbnails.assets.map do |asset|
          new_files = asset.paths.reject { |name, _| name == :original }
          new_files.map do |name, path|
            resources << Middleman::Sitemap::Resource.new(app.sitemap, name, path)
          end
        end

        resources
      end

      def thumbnails
        @thumbnails ||= Thumbnailer::Thumbnails.new(self, directories)
      end

      def before_build
        thumbnails.build
      end

      private

      def namespaced_images_directory
        [app.images_dir, (options[:namespace_directory] || []).join(',')].join('/')
      end

      def path_for(directory)
        File.join(app.source_dir, directory)
      end
    end
  end
end
