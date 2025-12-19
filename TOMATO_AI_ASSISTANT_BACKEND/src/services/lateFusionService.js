const supabaseService = require('./supabaseService');

class LateFusionService {
    async performLateFusion(imageResults, soilResults, userId, imageId, soilId) {
        try {
            console.log('Performing late fusion...');
            
            if (!imageResults?.success || !soilResults?.success) {
                throw new Error('Both image and soil analyses must be successful');
            }
            
            // VALIDATE REQUIRED FIELDS
            this.validateInputs(imageResults, soilResults);
            
            const tomatoType = imageResults.tomato_type;
            const healthStatus = imageResults.health_status;
            const diseaseType = imageResults.disease_type;
            const imageConfidence = imageResults.confidence_score || 0.5;
            const imageRecommendations = imageResults.recommendations || [];
            
            const soilStatus = soilResults.soil_status;
            const soilIssues = soilResults.soil_issues || [];
            const soilConfidence = soilResults.confidence_score || 0.5;
            const soilRecommendations = soilResults.recommendations || [];
            
            // REQUIRED numerical scores - FIX: Use correct field names
            const plantHealthScore = imageResults.plant_health_score || 0; // 0-100
            const soilQualityScore = soilResults.soil_quality_score || 0; // 0-100 - FIX: Use soil_quality_score
            
            // LOG scores for debugging/monitoring
            console.log('Fusion inputs - Plant:', plantHealthScore, 
                       'Soil:', soilQualityScore);
            
            // SIMPLE AVERAGE FUSION
            const averageScore = (plantHealthScore + soilQualityScore) / 2;
            const overallHealth = this.scoreToHealthCategory(averageScore);
            
            // LOG the fusion result
            console.log(`Fusion result: ${overallHealth} (Score: ${averageScore.toFixed(1)})`);
            
            const combinedConfidence = this.calculateCombinedConfidence(
                imageConfidence,
                soilConfidence
            );
            
            const combinedRecommendations = this.combineRecommendations(
                imageRecommendations,
                soilRecommendations
            );
            
            const fusedResult = {
                user_id: userId,
                image_id: imageId,
                soil_id: soilId,
                health_status: healthStatus,
                disease_type: diseaseType,
                soil_status: soilStatus,
                recommendations: this.formatForStorage(combinedRecommendations),
                combined_confidence_score: combinedConfidence,
                tomato_type: tomatoType,
                overall_health: overallHealth,  // Store the calculated category
                soil_issues: this.formatForStorage(soilIssues), // FIX: Include soil issues
                plant_health_score: plantHealthScore,
                soil_quality_score: soilQualityScore, // FIX: Use correct field name
                date_predicted: new Date(Date.now() + (8 * 60 * 60 * 1000)).toISOString()
            };
            
            console.log('📊 Fused result prepared:', {
                overall_health: fusedResult.overall_health,
                soil_quality_score: fusedResult.soil_quality_score,
                soil_issues: fusedResult.soil_issues,
                has_soil_data: !!soilId
            });
            
            const storedResult = await this.storeFusedResults(fusedResult);
            fusedResult.prediction_id = storedResult.prediction_id;
            
            console.log('✅ Late fusion completed successfully');
            
            return fusedResult;
            
        } catch (error) {
            console.error('❌ Late fusion failed:', error);
            throw new Error(`Late fusion failed: ${error.message}`);
        }
    }

    // Fusion for batch results
 async fuseSinglePair(imageResult, soilAnalysis, userId, imageId, soilId) {
    try {
        console.log('🔄 Fusing single image-soil pair...');
        
        if (!imageResult || !soilAnalysis) {
            throw new Error('Both image and soil analyses must be provided');
        }
        
        // Extract data with defaults
        const tomatoType = imageResult.tomato_type || 'Unknown';
        const healthStatus = imageResult.health_status || 'Unknown';
        const diseaseType = imageResult.disease_type || 'Unknown';
        const imageConfidence = parseFloat(imageResult.confidence_score) || 0.5;
        const imageRecommendations = imageResult.recommendations || [];
        
        const soilStatus = soilAnalysis.soil_status || 'Unknown';
        const soilIssues = soilAnalysis.soil_issues || [];
        const soilConfidence = parseFloat(soilAnalysis.confidence_score) || 0.5;
        const soilRecommendations = soilAnalysis.recommendations || [];
        
        // Get scores - ensure they exist
        const plantHealthScore = imageResult.plant_health_score !== undefined ? 
            parseFloat(imageResult.plant_health_score) : 50;
        const soilQualityScore = soilAnalysis.soil_quality_score !== undefined ? 
            parseFloat(soilAnalysis.soil_quality_score) : 50;
        
        console.log(`📊 Fusion scores - Plant: ${plantHealthScore}, Soil: ${soilQualityScore}`);
        
        // Calculate weighted average (adjust weights as needed)
        const plantWeight = 0.7;
        const soilWeight = 0.3;
        const combinedScore = (plantHealthScore * plantWeight) + (soilQualityScore * soilWeight);
        
        // Determine overall health based on combined score
        let overallHealth;
        if (combinedScore >= 80) overallHealth = 'Healthy';
        else if (combinedScore >= 60) overallHealth = 'Moderate';
        else if (combinedScore >= 40) overallHealth = 'Unhealthy';
        else if (combinedScore >= 20) overallHealth = 'Critical';
        else overallHealth = 'Unknown';
        
        // Calculate combined confidence
        const combinedConfidence = Math.round(((imageConfidence + soilConfidence) / 2) * 100) / 100;
        
        // Combine recommendations
        const allRecommendations = [...imageRecommendations, ...soilRecommendations];
        const uniqueRecommendations = this.removeDuplicates(allRecommendations);
        const prioritizedRecs = this.prioritizeRecommendations(uniqueRecommendations);
        
        // Create fused result
        const fusedResult = {
            user_id: userId,
            image_id: imageId,
            soil_id: soilId,
            health_status: healthStatus,
            disease_type: diseaseType,
            soil_status: soilStatus,
            recommendations: this.formatForStorage(prioritizedRecs),
            combined_confidence_score: combinedConfidence,
            tomato_type: tomatoType,
            overall_health: overallHealth,
            soil_issues: this.formatForStorage(soilIssues),
            plant_health_score: plantHealthScore,
            soil_quality_score: soilQualityScore,
            has_soil_data: !!soilId,
            mode: 'batch_integrated'
        };
        
        console.log(`✅ Fusion completed: ${overallHealth} (Score: ${combinedScore.toFixed(1)})`);
        
        return fusedResult;
        
    } catch (error) {
        console.error('❌ Single pair fusion failed:', error);
        // Return a fallback result
        return {
            user_id: userId,
            image_id: imageId,
            soil_id: soilId,
            health_status: 'Error',
            disease_type: 'Fusion Failed',
            soil_status: 'Error',
            recommendations: 'Check system configuration',
            combined_confidence_score: 0,
            tomato_type: 'Not Tomato',
            overall_health: 'Unknown',
            soil_issues: 'Fusion process error',
            plant_health_score: null,
            soil_quality_score: null,
            has_soil_data: !!soilId,
            mode: 'batch_integrated'
        };
    }
}

    // SIMPLE VALIDATION
    validateInputs(imageResults, soilResults) {
        // Quick validation - can be expanded
        if (imageResults.plant_health_score === undefined) {
            console.warn('⚠️ Image analysis missing plant_health_score, using 0');
        }
        if (soilResults.soil_quality_score === undefined) {
            console.warn('⚠️ Soil analysis missing soil_quality_score, using 0');
        }
        
        // Optional: Validate ranges
        const plantScore = imageResults.plant_health_score || 0;
        const soilScore = soilResults.soil_quality_score || 0; // FIX: Use correct field name
        
        if (plantScore < 0 || plantScore > 100 || 
            soilScore < 0 || soilScore > 100) {
            console.warn(`⚠️ Scores out of expected range: Plant=${plantScore}, Soil=${soilScore}`);
        }
    }

    // FIXED CATEGORIZATION FUNCTION
    scoreToHealthCategory(score) {
        if (score >= 80) return 'Healthy';
        if (score >= 60) return 'Moderate';
        if (score >= 40) return 'Unhealthy';
        if (score >= 20) return 'Critical';
        return 'Unknown';
    }

    // SIMPLE CONFIDENCE AVERAGE
    calculateCombinedConfidence(imageConfidence, soilConfidence) {
        const imgConf = Number(imageConfidence) || 0.5;
        const soilConf = Number(soilConfidence) || 0.5;
        return Math.round(((imgConf + soilConf) / 2) * 100) / 100;
    }

    // EXISTING HELPER METHODS
    combineRecommendations(imageRecs, soilRecs) {
        const allRecommendations = [...imageRecs, ...soilRecs];
        const uniqueRecommendations = this.removeDuplicates(allRecommendations);
        return this.prioritizeRecommendations(uniqueRecommendations);
    }

    removeDuplicates(recommendations) {
        const seen = new Set();
        return recommendations.filter(rec => {
            if (!rec || typeof rec !== 'string') return false;
            const normalized = rec.toLowerCase().trim();
            if (seen.has(normalized)) return false;
            seen.add(normalized);
            return true;
        });
    }

    prioritizeRecommendations(recommendations) {
        const highPriorityKeywords = ['immediate', 'urgent', 'critical', 'severe', 'destroy', 'remove'];
        const mediumPriorityKeywords = ['apply', 'treat', 'fungicide', 'fertilizer', 'nutrient', 'water'];
        const lowPriorityKeywords = ['maintain', 'continue', 'monitoring', 'prevent'];
        
        const prioritized = { high: [], medium: [], low: [] };
        
        recommendations.forEach(rec => {
            const lowerRec = rec.toLowerCase();
            
            if (highPriorityKeywords.some(keyword => lowerRec.includes(keyword))) {
                prioritized.high.push(rec);
            } else if (mediumPriorityKeywords.some(keyword => lowerRec.includes(keyword))) {
                prioritized.medium.push(rec);
            } else if (lowPriorityKeywords.some(keyword => lowerRec.includes(keyword))) {
                prioritized.low.push(rec);
            } else {
                prioritized.medium.push(rec);
            }
        });
        
        return [...prioritized.high, ...prioritized.medium, ...prioritized.low];
    }

    formatForStorage(items) {
        if (!items || items.length === 0) return 'No issues found';
        if (Array.isArray(items)) {
            return items.filter(item => item && item.trim()).join('; ');
        }
        return String(items);
    }

    async storeFusedResults(fusedResult) {
        console.log('💾 Storing fused results in database...');
        console.log('📊 Fused data to store:', {
            overall_health: fusedResult.overall_health,
            soil_quality_score: fusedResult.soil_quality_score,
            soil_issues: fusedResult.soil_issues,
            has_soil_data: !!fusedResult.soil_id
        });

        const { data, error } = await supabaseService.client
            .from('prediction_results')
            .insert({
                user_id: fusedResult.user_id,
                image_id: fusedResult.image_id,
                soil_id: fusedResult.soil_id,
                date_predicted: fusedResult.date_predicted,
                health_status: fusedResult.health_status,
                disease_type: fusedResult.disease_type,
                soil_status: fusedResult.soil_status,
                recommendations: fusedResult.recommendations,
                combined_confidence_score: fusedResult.combined_confidence_score,
                tomato_type: fusedResult.tomato_type,
                overall_health: fusedResult.overall_health,
                soil_issues: fusedResult.soil_issues,
                plant_health_score: fusedResult.plant_health_score,
                soil_quality_score: fusedResult.soil_quality_score,
                has_soil_data: !!fusedResult.soil_id,
                mode: fusedResult.mode || 'integrated'
            })
            .select('prediction_id')
            .single();

        if (error) {
            console.error('❌ Database insert error:', error);
            throw error;
        }
        
        console.log('✅ Fused results stored successfully, ID:', data.prediction_id);
        return data;
    }
}

module.exports = LateFusionService;