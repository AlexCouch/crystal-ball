require "process"
require "dir"
require "time"
require "file"
require "fiber"
require "colorize"

module Watcher
    property last_update : Time = Time.local

    def preCommandExec
    end
    
    def postCommandExec
    end

    def initialize(@file : File, @command : String)
    end

    def start
        loop do
            if File.exists?(@file.path)
                stat = File.info @file.path
                if stat.modification_time > @last_update
                    # puts "Modification time: #{stat.modification_time}"
                    # puts "@last_update: #{@last_update}"
                    preCommandExec()
                    puts `#{@command}`
                    postCommandExec()
                    @last_update = stat.modification_time
                end
            end
            
            Fiber.yield
        end
    end
end

class ShardWatcher
    include Watcher
end

class SourceWatcher
    include Watcher

    def self.from_dir(start_dir : String)
        SourceWatcher.from_dir(Dir.new(start_dir))
    end

    def self.from_dir(start_dir : Dir)
        start_dir.each_child do |filename|
            # puts "Attempting to add watcher for #{filename}"
            path = Path.new(start_dir.path).join(Path.new(filename))
            # puts "Extension of file: #{path.extension}"
            case
            when path.extension == ".cr"
                source_watcher = SourceWatcher.new(File.new path)
                # puts "Adding source watcher for #{path}"
                spawn source_watcher.start
            when File.directory? path
                SourceWatcher.from_dir(path.to_s)
            end
        end
    end

    def initialize(file : File)
        initialize(file, "shards build")
    end

    def preCommandExec
        puts "Found changes to source file #{@file.path.colorize(:blue)}"
    end

    def postCommandExec
        puts "Compilation complete!"
    end
end

#Hello world
cwd = Dir.current
shard_yml : File = File.new(cwd + "/shard.yml")
shard_watcher = ShardWatcher.new(shard_yml, "shards update")
spawn shard_watcher.start
SourceWatcher.from_dir(cwd)
loop do
    Fiber.yield
end