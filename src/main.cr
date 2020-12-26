require "process"
require "dir"
require "time"
require "file"
require "fiber"
require "colorize"

module Watcher
    property last_update : Time = Time.local
    getter file : File
    getter command : String

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
                    puts "Executing command from cwd: #{Dir.current}"
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

    def self.from_file(file : File) : SourceWatcher?
        # puts "Attempting to add watcher for #{filename}"
        path = Path.new(file.path)
        info = File.info(Path.new(file.path), follow_symlinks: false)
        if info.symlink?
            return nil
        end
        if File.directory? file.path
            nil
        else
            if(path.extension != ".cr")
                return nil
            end
            new(file, "shards build")
        end
    end

    def preCommandExec
        puts "Found changes to source file #{@file.path.colorize(:blue)}"
    end

    def postCommandExec
        puts "Compilation complete!"
    end
end

class WatcherManager
    getter watchers = [] of Watcher

    def from_dir(dir : Dir)
        puts "Attempting to create source watchers from directory: #{dir.path}"
        dir.each_child { |child_path|
            path = Path.new(dir.path).join(Path.new(child_path))
            file = File.new path
            info = File.info(path, follow_symlinks: false)
            if info.symlink?
                next
            end
            if File.directory? file.path
                from_dir Dir.new(file.path)
                next
            end
            watcher = SourceWatcher.from_file(file)
            if watcher.nil?
                next
            end
            new_watcher = watcher.as(SourceWatcher)
            spawn new_watcher.start
            @watchers << new_watcher
        }
    end

    def start
        cwd = Dir.current
        cwd_dir = Dir.new cwd
        shard_yml : File = File.new(cwd + "/shard.yml")
        shard_watcher = ShardWatcher.new(shard_yml, "shards update")
        spawn shard_watcher.start
        watchers << shard_watcher
        from_dir(cwd_dir)
        loop do
            cwd_dir.each_child { |child|
                if @watchers.find { |watcher| watcher.file.path == child }.nil?
                    puts "Foudn new file, attempting to create new source watchers if possible..."
                    path = Path.new(cwd_dir).join(Path.new(child))
                    if File.directory? child
                        from_dir(Dir.new(child))
                    else
                        file = File.new path
                        new_source_watcher = SourceWatcher.from_file file
                        if new_source_watcher.nil?
                            next
                        end
                        watcher = new_source_watcher.as(SourceWatcher)
                        @watchers << watcher
                        spawn watcher.start
                    end
                end
            }
            Fiber.yield
        end
    end
end

watcher_manager = WatcherManager.new
spawn watcher_manager.start
loop do
    Fiber.yield
end