module Scene
  module MaterialCatalog
    MATERIALS = {
      "grass" => { color: "#6f9258", roblox: 1280 },
      "earth" => { color: "#705747", roblox: 1360 },
      "sand" => { color: "#d9c48f", roblox: 800 },
      "water" => { color: "#5aa9c9", roblox: 272 },
      "stone" => { color: "#92989a", roblox: 896 },
      "concrete" => { color: "#c7c5bb", roblox: 816 },
      "path" => { color: "#c7b99c", roblox: 880 },
      "wood" => { color: "#9b724d", roblox: 512 },
      "dark_wood" => { color: "#5b4231", roblox: 528 },
      "metal" => { color: "#596269", roblox: 1088 },
      "foliage" => { color: "#3f7448", roblox: 1280 },
      "foliage_light" => { color: "#6f9b58", roblox: 1280 },
      "evergreen" => { color: "#244f3c", roblox: 1280 },
      "flower_mix" => { color: "#d85b72", roblox: 512 },
      "flower_red" => { color: "#c92f3f", roblox: 512 },
      "flower_orange" => { color: "#ed6c32", roblox: 512 },
      "flower_pink" => { color: "#ed78a6", roblox: 512 },
      "flower_yellow" => { color: "#f1c84b", roblox: 512 },
      "flower_purple" => { color: "#8958a8", roblox: 512 },
      "flower_white" => { color: "#f4efe7", roblox: 512 },
      "mountain" => { color: "#526b78", roblox: 896 },
      "bark" => { color: "#654737", roblox: 512 },
      "roof" => { color: "#754d42", roblox: 2308 },
      "white" => { color: "#edeae1", roblox: 2310 },
      "glass" => { color: "#a9d5df", roblox: 1568 }
    }.freeze

    module_function

    def fetch(name)
      MATERIALS.fetch(name)
    end

    def names
      MATERIALS.keys
    end
  end
end
