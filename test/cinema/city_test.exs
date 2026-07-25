defmodule Cinema.CityTest do
  use ExUnit.Case, async: true

  alias Cinema.City

  describe "slug/1" do
    test "is derived from the name, never from the source's own id" do
      # The public URL must not leak which site the data comes from: a source
      # change would otherwise break every bookmark.
      assert City.slug("Grenoble") == "grenoble"
      assert City.slug("Lyon") == "lyon"
    end

    test "strips accents so the slug is URL-safe" do
      assert City.slug("Nîmes") == "nimes"
      assert City.slug("Béziers") == "beziers"
    end

    test "joins words with a single hyphen" do
      assert City.slug("Le Mans") == "le-mans"
      assert City.slug("Aix-en-Provence") == "aix-en-provence"
      assert City.slug("Clermont-Ferrand") == "clermont-ferrand"
    end

    test "drops punctuation rather than encoding it" do
      assert City.slug("L'Haÿ-les-Roses") == "l-hay-les-roses"
      assert City.slug("Saint-Étienne") == "saint-etienne"
    end

    test "never produces leading, trailing or doubled hyphens" do
      assert City.slug("  Le   Mans  ") == "le-mans"
      assert City.slug("Île-de-Ré") == "ile-de-re"
    end
  end

  test "new/2 builds a city whose slug is public and whose id stays internal" do
    city = City.new("ville-98857", "Grenoble")

    assert city.slug == "grenoble"
    assert city.name == "Grenoble"
    assert city.external_id == "ville-98857"
  end
end
