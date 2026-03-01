require 'fileutils'

# Liste des fichiers à mettre à jour
csv_files = %w[
  Data/Text/Dialogs/110000.csv
  Data/Text/Dialogs/110001.csv
]

csv_files.each do |file_path|
  if File.exist?(file_path)
    puts 'CSV update required? : true'
    puts "#{file_path} deleted to be added again."
    File.delete(file_path)
  else
    puts 'CSV update required? : false'
    puts "#{file_path} does not exist."
  end
end
