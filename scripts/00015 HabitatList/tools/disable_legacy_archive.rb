# Run once from any directory. Keeps the original archive and every resource.
# Uses PSDK's own virtual-directory implementation and signature validation.
require 'digest'
require 'stringio'
require 'fileutils'

scripts = File.expand_path('../..', __dir__)
source_path = File.join(scripts, 'psdk_scripts/0_Dependencies.rb')
source = File.read(source_path, encoding: 'UTF-8')
vd_source = source[/^  class VD\n.*?(?=^  class GifReader)/m]
raise 'Cannot locate the local Yuki::VD implementation' unless vd_source
eval("module Yuki\n#{vd_source}\nend", TOPLEVEL_BINDING, source_path)
require File.join(scripts, 'psdk_scripts/tools/PluginManager')
PSDK_VERSION = 6716

archive = File.join(scripts, 'HabitatList.psdkplug')
backup = "#{archive}.disabled"
legacy_path = 'scripts/54000 Dex_Zones.rb'
FileUtils.cp(archive, backup) unless File.exist?(backup)
original = Yuki::VD.new(backup, :read)
config = Marshal.load(original.read_data("\x00"))
raise 'Unexpected plugin' unless config.name == 'HabitatList'
raise 'Legacy script missing' unless original.read_data(legacy_path)
target = "#{archive}.migration-tmp"
writer = Yuki::VD.new(target, :write)
original.get_filenames.each do |name|
  next if name == "\x00"

  data = original.read_data(name)
  if name == legacy_path
    data = "# Disabled for PSDK 26.60. See scripts/00015 HabitatList/MIGRATION.md.\n" +
           data.lines.map { |line| "# #{line}" }.join
  end
  writer.write_data(name, data)
end
original.close
writer.close
size = File.binread(target, Yuki::VD::POINTER_SIZE).unpack1(Yuki::VD::UNPACK_METHOD)
config.sha512 = Digest::SHA512.hexdigest(File.binread(target, size - 4, 4))
writer = Yuki::VD.new(target, :update)
writer.write_data("\x00", Marshal.dump(config))
writer.close
PluginManager::LoadedPlugin.new(target) # Validate before replacing anything.
FileUtils.cp(target, archive)
File.delete(target)
puts 'HabitatList archive disabled; original preserved as HabitatList.psdkplug.disabled.'
