namespace :scenes do
  desc "Compile the three development SceneSpecs and generate editable .rbxlx maps"
  task generate: :environment do
    output_dir = Rails.root.join("generated_maps")
    FileUtils.mkdir_p(output_dir)
    report = {}

    Dir[Rails.root.join("examples/*.json")].sort.each do |path|
      spec = JSON.parse(File.read(path))
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      scene_ir = Scene::Compiler.new.compile_scene(spec)
      xml = Roblox::Exporter.new.export(scene_ir)
      name = File.basename(path, ".json")
      File.write(output_dir.join("#{name}.rbxlx"), xml)
      report[name] = scene_ir.fetch("stats").merge(
        "total_generate_ms" => ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2),
        "spec_digest" => scene_ir.fetch("spec_digest"),
        "rbxlx_bytes" => xml.bytesize
      )
      puts "#{name}: #{scene_ir.dig("stats", "part_count")} parts, #{report[name]["total_generate_ms"]} ms"
    end

    File.write(output_dir.join("generation_metrics.json"), JSON.pretty_generate(report) + "\n")
  end
end
