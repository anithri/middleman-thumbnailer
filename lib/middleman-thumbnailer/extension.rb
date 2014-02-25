require 'middleman-thumbnailer/thumbnail-generator'

module Middleman
  module Thumbnailer
    class << self

      attr_accessor :options

      def registered(app, options={})

        options[:filetypes] ||= [:jpg, :jpeg, :png]
        options[:include_data_thumbnails] = false unless options.has_key? :include_data_thumbnails
        options[:namespace_directory] = ["**"] unless options.has_key? :namespace_directory

        Thumbnailer.options = options

        app.helpers Helpers

        app.after_configuration do

          options[:build_dir] = build_dir

          #stash the source images dir in options for the Rack middleware
          options[:images_source_dir] = File.join(source_dir, images_dir)
          options[:source_dir] = source_dir

          dimensions = options[:dimensions]
          namespace = options[:namespace_directory]

          app.before_build do
            dir = File.join(source_dir, images_dir)


            files = DirGlob.glob(dir, namespace, options[:filetypes])

            files.each do |file|
              path = file.gsub(source_dir, '')
              specs = ThumbnailGenerator.specs(path, dimensions)
              ThumbnailGenerator.generate(source_dir, File.join(root, build_dir), path, specs)
            end
          end

          sitemap.register_resource_list_manipulator(:thumbnailer, SitemapExtension.new(self), true)

          app.use Rack, options
        end
      end
      alias :included :registered
    end

    module Helpers
      def thumbnail_specs(image, name)
        dimensions = Thumbnailer.options[:dimensions]
        ThumbnailGenerator.specs(image, dimensions)
      end

      def thumbnail_url(image, name, options = {})
        include_images_dir = options.delete :include_images_dir

        url = thumbnail_specs(image, name)[name][:name]
        url = File.join(images_dir, url) if include_images_dir

        url
      end

      def thumbnail(image, name, html_options = {})
        specs_for_data_attribute = thumbnail_specs(image, name).map {|name, spec| "#{name}:#{spec[:name]}"}

        html_options.merge!({'data-thumbnails' => specs_for_data_attribute.join('|')}) if Thumbnailer.options[:include_data_thumbnails]

        image_tag(thumbnail_url(image, name), html_options)
      end
    end

    class DirGlob
      def self.glob(root, namespaces, filetypes)
        filetypes_with_capitals = filetypes.reduce([]) { |memo, file| memo.concat [file, file.upcase] }
        glob_str = "#{root}/#{namespaces.join(',')}/**/*.{#{filetypes_with_capitals.join(',')}}"
        Dir[glob_str]
      end
    end

    class SitemapExtension
      def initialize(app)
        @app = app
      end

      # Add sitemap resource for every image in the sprockets load path
      def manipulate_resource_list(resources)

        images_dir_abs = File.join(@app.source_dir, @app.images_dir)

        images_dir = @app.images_dir

        options = Thumbnailer.options
        dimensions = options[:dimensions]
        namespace = options[:namespace_directory].join(',')

        files = DirGlob.glob(images_dir_abs, options[:namespace_directory], options[:filetypes])

        resource_list = files.map do |file|
          path = file.gsub(@app.source_dir + File::SEPARATOR, '')
          specs = ThumbnailGenerator.specs(path, dimensions)
          specs.map do |name, spec|
            resource = nil
            resource = Middleman::Sitemap::Resource.new(@app.sitemap, spec[:name], File.join(options[:build_dir], spec[:name])) unless name == :original
          end
        end.flatten.reject {|resource| resource.nil? }

        resources + resource_list
      end

    end


    # Rack middleware to convert images on the fly
    class Rack

      # Init
      # @param [Class] app
      # @param [Hash] options
      def initialize(app, options={})
        @app = app
        @options = options

        files = DirGlob.glob(options[:images_source_dir], options[:namespace_directory], options[:filetypes])

        @original_map = ThumbnailGenerator.original_map_for_files(files, options[:dimensions])

      end

      # Rack interface
      # @param [Rack::Environmemt] env
      # @return [Array]
      def call(env)
        status, headers, response = @app.call(env)

        path = env["PATH_INFO"]

        absolute_path = File.join(@options[:source_dir], path)

        #TODO: caching
        if original_specs = @original_map[absolute_path]
          original_file = original_specs[:original]
          image = ThumbnailGenerator.image_for_spec(original_file, original_specs[:spec])
          blob = image.to_blob
          status = 200
          headers["Content-Length"] = ::Rack::Utils.bytesize(blob).to_s
          headers["Content-Type"] = image.mime_type
          response = [blob]
        end

        [status, headers, response]
      end
    end
  end
end
