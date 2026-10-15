--[[
  Joueurs inventés du circuit : prénoms et noms imaginaires par pays.
  (Toute ressemblance avec des joueurs réels serait fortuite.)
]]

local Names = {}

Names.COUNTRIES = {
    { id = "be", name = "Belgique", first = { "Arnaud", "Maëlle", "Thibault", "Elise", "Quentin", "Louise", "Cédric", "Noémie", "Bastien", "Amandine", "Jérôme", "Hélène" },
      last = { "Vandenbroeck", "Lemaître", "Dussart", "Wauters", "Delvaux", "Mertens", "Collignon", "Hennebert", "Lambotte", "Pirard", "Verhaegen", "Gilson" } },
    { id = "fr", name = "France", first = { "Julien", "Camille", "Mathis", "Chloé", "Antoine", "Léa", "Romain", "Inès", "Hugo", "Clémence", "Bertrand", "Manon" },
      last = { "Garnier", "Rousseau", "Delorme", "Fabre", "Marchal", "Lefort", "Bonnaire", "Chevalier", "Morin", "Perrot", "Vasseur", "Langlois" } },
    { id = "uk", name = "Angleterre", first = { "Oliver", "Harriet", "George", "Imogen", "Alfie", "Poppy", "Rupert", "Freya", "Callum", "Esme", "Hugh", "Matilda" },
      last = { "Ashworth", "Pembroke", "Hartley", "Whitcombe", "Fairfax", "Holloway", "Thorne", "Kingsley", "Marlow", "Brampton", "Ellery", "Calloway" } },
    { id = "es", name = "Espagne", first = { "Javier", "Lucía", "Álvaro", "Carmen", "Diego", "Paula", "Sergio", "Nerea", "Iker", "Marta", "Rubén", "Elena" },
      last = { "Ortega", "Navarro", "Castillo", "Herrera", "Peñalver", "Montoya", "Vidal", "Cabrera", "Salgado", "Iglesias", "Robles", "Aranda" } },
    { id = "it", name = "Italie", first = { "Lorenzo", "Giulia", "Matteo", "Chiara", "Davide", "Francesca", "Tommaso", "Alessia", "Riccardo", "Beatrice", "Pietro", "Sofia" },
      last = { "Bellandi", "Ferraresi", "Martinelli", "Cattaneo", "Lombardo", "Benedetti", "Moretti", "Santoro", "Galli", "Rinaldi", "Costanzo", "Valeri" } },
    { id = "de", name = "Allemagne", first = { "Lukas", "Hannah", "Felix", "Lena", "Jonas", "Clara", "Moritz", "Anja", "Tobias", "Katrin", "Florian", "Greta" },
      last = { "Brandt", "Lindemann", "Hoffbauer", "Kessler", "Vogt", "Reinhardt", "Albrecht", "Seidel", "Engel", "Hartwig", "Böhm", "Kraus" } },
    { id = "hu", name = "Hongrie", first = { "Bence", "Réka", "Levente", "Zsófia", "Máté", "Dóra", "Gergely", "Eszter", "Áron", "Noémi", "Csaba", "Anna" },
      last = { "Kovács", "Szilágyi", "Halász", "Varga", "Bodnár", "Fekete", "Molnár", "Takács", "Kertész", "Simon", "Fazekas", "Pintér" } },
    { id = "is", name = "Islande", first = { "Gunnar", "Sigrún", "Einar", "Katrín", "Hrafn", "Ásta", "Bjarki", "Elín", "Ragnar", "Hildur", "Þórir", "Brynja" },
      last = { "Einarsson", "Gunnarsdóttir", "Sveinsson", "Hallsdóttir", "Bergsson", "Ragnarsdóttir", "Ásgeirsson", "Kristjánsdóttir", "Þorvaldsson", "Ingólfsdóttir", "Helgason", "Arnardóttir" } },
    { id = "ar", name = "Argentine", first = { "Mateo", "Valentina", "Santiago", "Camila", "Tomás", "Florencia", "Nicolás", "Martina", "Joaquín", "Agustina", "Facundo", "Rocío" },
      last = { "Ferreyra", "Benítez", "Quiroga", "Medina", "Arce", "Villalba", "Sosa", "Ledesma", "Aguirre", "Ojeda", "Maidana", "Correa" } },
    { id = "jp", name = "Japon", first = { "Haruto", "Yui", "Sota", "Aoi", "Ren", "Hina", "Kaito", "Sakura", "Daiki", "Mio", "Takumi", "Rin" },
      last = { "Takahara", "Moriyama", "Kanzaki", "Fujisawa", "Hayakawa", "Ishimura", "Nakagawa", "Okabe", "Sugimoto", "Uchida", "Kuroda", "Mizuno" } },
}

function Names.country(id)
    for _, c in ipairs(Names.COUNTRIES) do
        if c.id == id then return c end
    end
    return Names.COUNTRIES[1]
end

-- Génère un nom unique (used = table des noms déjà pris)
function Names.random(rnd, used, countryId)
    rnd = rnd or math.random
    for _ = 1, 200 do
        local c = countryId and Names.country(countryId) or Names.COUNTRIES[math.floor(rnd() * #Names.COUNTRIES) + 1]
        local f = c.first[math.floor(rnd() * #c.first) + 1]
        local l = c.last[math.floor(rnd() * #c.last) + 1]
        local full = f .. " " .. l
        if not used or not used[full] then
            if used then used[full] = true end
            return full, c.id
        end
    end
    return "Joueur " .. math.floor(rnd() * 10000), "be"
end

return Names
