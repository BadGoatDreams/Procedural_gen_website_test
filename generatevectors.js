console.log("generateVectors.js loaded - generating map on load using OpenSimplex Noise.");

// --- Configuration Parameters ---
const mapWidth = 512;
const mapHeight = 512;
const noiseScale = 120.0;
const noiseOctaves = 5;
const noisePersistence = 0.5;
const noiseLacunarity = 2.0;
const seaLevel = 0.48;
const gradientPower = 1.8; // Controls how quickly land drops off towards edges

// Map bounds
const minX = 0;
const minY = 0;
const maxX = mapWidth;
const maxY = mapHeight;

// --- DOM Elements ---
const mapElement = document.getElementById('map');

// --- Leaflet Map Initialization ---
let map = null;
let landLayer = null;
let oceanLayer = null;

if (typeof L !== 'undefined') {
    map = L.map(mapElement, {
         crs: L.CRS.Simple,
         minZoom: -3
        }).setView([maxY / 2, maxX / 2], -1);
    console.log("Leaflet map initialized.");
} else {
    console.error("Leaflet library not loaded!");
    if(mapElement) mapElement.innerHTML = "Error: Leaflet map library failed to load.";
}

// --- Main Generation Function ---
function generateMapVectors() {
    if (!map) {
        console.error("Map not initialized. Cannot generate vectors.");
        return;
    }

    // --- Check if the openSimplexNoise function loaded ---
    if (typeof openSimplexNoise !== 'function') {
        console.error("openSimplexNoise function not found! Make sure openSimplexNoise.js is loaded correctly before generateVectors.js.");
        if(mapElement) mapElement.innerHTML = "Error: Noise library function (openSimplexNoise) not found. Check console.";
        return;
    }
    // ----------------------------------------------------

    console.log("Generation started...");

    // Clear previous layers
    if (landLayer) map.removeLayer(landLayer);
    if (oceanLayer) map.removeLayer(oceanLayer);
    landLayer = null;
    oceanLayer = null;

    try {
        // --- Instantiate OpenSimplex Noise ---
        const seed = Date.now(); // Use current time for a random seed each time
        // const seed = 12345; // Or use a fixed number for reproducible maps
        console.log(`Using OpenSimplex Noise with seed: ${seed}`);
        const noiseGenerator = openSimplexNoise(seed);
        const noise2D = noiseGenerator.noise2D; // Get the specific 2D noise function

        // Optional: Check if noise2D is actually a function now
        if (typeof noise2D !== 'function') {
             console.error("Failed to get noise2D function from openSimplexNoise generator!");
             if(mapElement) mapElement.innerHTML = "Error: Could not initialize noise function. Check console.";
             return;
        }
        // --- End Noise Instantiation ---


        // 1. Generate Base Noise & Apply Gradient
        console.log("Generating noise map...");
        const noiseValues = new Float32Array(mapWidth * mapHeight);
        const gradientValues = new Float32Array(mapWidth * mapHeight);
        const finalValues = new Float32Array(mapWidth * mapHeight);

        const centerX = mapWidth / 2.0;
        const centerY = mapHeight / 2.0;
        const maxDist = Math.sqrt(centerX * centerX + centerY * centerY); // Furthest distance from center

        for (let y = 0; y < mapHeight; y++) {
            for (let x = 0; x < mapWidth; x++) {
                const index = y * mapWidth + x;

                // Generate OpenSimplex noise summed over octaves
                let noiseVal = 0;
                let amplitude = 1.0;
                let frequency = 1.0;
                for(let o = 0; o < noiseOctaves; o++){
                    // --- Call the obtained noise2D function directly ---
                    // Note: No need for .createNoise2D() anymore
                    noiseVal += noise2D(x * frequency / noiseScale, y * frequency / noiseScale) * amplitude;
                    // -------------------------------------------------
                    amplitude *= noisePersistence;
                    frequency *= noiseLacunarity;
                }
                noiseValues[index] = noiseVal; // Store raw noise

                // Calculate gradient (stronger towards center, weaker at edges)
                const dx = x - centerX;
                const dy = y - centerY;
                const dist = Math.sqrt(dx * dx + dy * dy);
                const normDist = dist / maxDist; // Normalized distance (0 center, 1 edge)
                // Gradient makes edges lower (more likely ocean)
                gradientValues[index] = Math.max(0.0, Math.min(1.0, 1.0 - Math.pow(normDist, gradientPower)));
            }
        }

        // Normalize noise (typically -1 to 1 range) and apply gradient
        let minN = Infinity, maxN = -Infinity;
         for(let i=0; i<noiseValues.length; i++) {
             if(noiseValues[i] < minN) minN = noiseValues[i];
             if(noiseValues[i] > maxN) maxN = noiseValues[i];
         }
         console.log(`Raw noise range: ${minN.toFixed(3)} to ${maxN.toFixed(3)}`);

        if (maxN > minN) {
            const rangeN = maxN - minN;
            for(let i=0; i<noiseValues.length; i++) {
                const normalizedNoise = (noiseValues[i] - minN) / rangeN; // Normalize 0-1
                finalValues[i] = normalizedNoise * gradientValues[i]; // Apply gradient
            }
        } else { // Handle case where noise is flat (unlikely but possible)
            console.warn("Noise range is zero. Applying gradient only.");
            for(let i=0; i<noiseValues.length; i++) { finalValues[i] = 0.5 * gradientValues[i]; }
        }
        console.log("Noise generated and gradient applied.");


        // 2. Vectorize Landmass using d3-contour
        console.log("Vectorizing landmass...");
        const contourGenerator = d3.contours()
            .size([mapWidth, mapHeight])
            .thresholds([seaLevel, 1.01]); // Thresholds for contouring: [seaLevel, slightly_above_max]

        const contours = contourGenerator(finalValues); // Generate contours from the final height values
        const landGeometry = contours[0]; // The first contour is everything >= seaLevel
        let landFeature = null;

        if (landGeometry && landGeometry.coordinates && landGeometry.coordinates.length > 0) {
             landFeature = { type: "Feature", properties: { type: "land" }, geometry: landGeometry };
             console.log("Landmass vectorized.");
        } else {
            console.log("No land generated above sea level.");
        }

        // 3. Generate Ocean Polygon using Turf.js
        console.log("Generating ocean polygon...");
        const mapBoundsPolygon = turf.polygon([[ [minX, minY], [maxX, minY], [maxX, maxY], [minX, maxY], [minX, minY] ]]);
        let oceanFeature = null;
        const landTurfFeature = landFeature ? turf.feature(landGeometry) : null;

        if (landTurfFeature) {
            try {
                // Use turf.difference to subtract the land shape from the map bounds
                // Ensure the land polygon is valid for turf operations
                const cleanedLand = turf.cleanCoords(landTurfFeature); // Attempt to clean up coordinates
                const validLand = turf.buffer(cleanedLand, 0); // Buffer by 0 can sometimes fix topology issues

                const oceanGeometry = turf.difference(mapBoundsPolygon, validLand);
                if (oceanGeometry) {
                     oceanFeature = { type: "Feature", properties: { type: "ocean" }, geometry: oceanGeometry.geometry };
                     console.log("Ocean polygon generated.");
                } else {
                    console.warn("Turf.difference resulted in null. Ocean may cover full extent.");
                }
            } catch (e) {
                console.error("Error during Turf.difference:", e);
                // Fallback: ocean covers everything if difference fails
            }
        }

        // If ocean wasn't created (no land or error), make it cover the whole map
        if (!oceanFeature) {
            oceanFeature = { type: "Feature", properties: { type: "ocean" }, geometry: mapBoundsPolygon.geometry };
            if (!landTurfFeature) console.log("No land found, ocean covers full extent.");
            else console.log("Using full extent for ocean due to difference error or null result.");
        }

        // 4. Add Layers to Leaflet Map
        console.log("Adding layers to map...");
        if (oceanFeature) {
            oceanLayer = L.geoJSON(oceanFeature, { style: { color: "#007bff", weight: 1, fillColor: "#aaccff", fillOpacity: 0.6 } }).addTo(map);
        }
        if (landFeature) {
            landLayer = L.geoJSON(landFeature, { style: { color: "#28a745", weight: 1, fillColor: "#77dd77", fillOpacity: 0.8 } }).addTo(map);
        }
        map.fitBounds([[minY, minX], [maxY, maxX]], {padding: [20, 20]}); // Fit map view to bounds
        console.log("Generation finished and map updated.");

    } catch (error) {
        console.error("Generation failed:", error);
        if(mapElement) mapElement.innerHTML = `Error during map generation: ${error.message}. Check console for details.`;
    }
}
//what

// --- Auto-run on Load ---
// Make sure the DOM is ready before running the generation
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', generateMapVectors);
} else {
    generateMapVectors(); // DOMContentLoaded has already fired
}

// Optional: Regenerate on button click (Example)
/*
const regenButton = document.createElement('button');
regenButton.textContent = 'Regenerate Map';
regenButton.style.position = 'absolute';
regenButton.style.top = '10px';
regenButton.style.left = '50px';
regenButton.style.zIndex = 1000; // Ensure it's on top
regenButton.onclick = generateMapVectors;
document.body.appendChild(regenButton);
*/