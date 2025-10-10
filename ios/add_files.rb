#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = 'QCSDKDemo.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.find { |t| t.name == 'QCSDKDemo' }

# List of files to add
files_to_add = [
  'QGDeviceStatusView.h',
  'QGDeviceStatusView.m',
  'QGMediaInfoView.h',
  'QGMediaInfoView.m',
  'QGUIModularizer.h',
  'QGUIModularizer.m',
  'QGProgressiveUIEnhancer.h',
  'QGProgressiveUIEnhancer.m',
  'QGUIColumnsManager.h',
  'QGUIColumnsManager.m'
]

# Get the main group
main_group = project.main_group.find_subpath('QCSDKDemo')

# Add each file
files_to_add.each do |filename|
  file_path = "QCSDKDemo/#{filename}"

  # Check if file exists
  if File.exist?(file_path)
    # Create file reference
    file_ref = main_group.new_file(filename)

    # Add to target if it's an implementation file
    if filename.end_with?('.m')
      target.add_file_references([file_ref])
    end

    puts "Added #{filename} to project"
  else
    puts "Warning: #{file_path} not found"
  end
end

# Save the project
project.save

puts "Project updated successfully!"