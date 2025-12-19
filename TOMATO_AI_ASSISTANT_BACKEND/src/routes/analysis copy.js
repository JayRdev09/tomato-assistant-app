const express = require('express');
const router = express.Router();
const storageService = require('../services/storageService');
const mlService = require('../services/mlService');

// Initialize ML model on startup
console.log('🚀 Initializing ML service...');
mlService.initialize().then(() => {
  const health = mlService.healthCheck();
  console.log('✅ ML service initialization completed:', {
    initialized: health.initialized,
    model_loaded: health.model_loaded,
    runtime: health.runtime
  });
}).catch(error => {
  console.error('❌ ML service initialization failed:', error);
});

// ML service status endpoint
router.get('/ml-status', async (req, res) => {
  try {
    const mlHealth = mlService.healthCheck();
    
    res.json({
      success: true,
      ml_service: {
        initialized: mlHealth.initialized,
        model_loaded: mlHealth.model_loaded,
        using_tflite: mlHealth.initialized,
        fallback_mode: !mlHealth.initialized,
        class_count: mlHealth.class_count,
        runtime: mlHealth.runtime,
        supports_tflite: mlHealth.supports_tflite
      },
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ ML status check failed:', error);
    res.status(500).json({
      success: false,
      message: 'ML status check failed: ' + error.message
    });
  }
});

// Check data status for analysis - FIXED response structure
router.get('/data-status', async (req, res) => {
  try {
    const userId = req.query.userId;
    
    if (!userId) {
      return res.status(400).json({
        success: false,
        message: 'User ID is required'
      });
    }
    
    console.log(`📊 Checking data status for user ${userId}...`);
    
    // Get latest soil data
    const latestSoil = await storageService.getLatestSoilData(userId);
    console.log('Soil data status:', latestSoil ? 'found' : 'not found');
    
    // Get latest image
    const latestImage = await storageService.getLatestImage(userId);
    console.log('Image data status:', latestImage ? 'found' : 'not found');
    
    // Calculate data age in hours
    const now = new Date();
    let soilAgeHours = null;
    let imageAgeHours = null;
    
    if (latestSoil && latestSoil.timestamp) {
      const soilTime = new Date(latestSoil.timestamp);
      soilAgeHours = (now - soilTime) / (1000 * 60 * 60);
    }
    
    if (latestImage && latestImage.timestamp) {
      const imageTime = new Date(latestImage.timestamp);
      imageAgeHours = (now - imageTime) / (1000 * 60 * 60);
    }
    
    // Determine if data is fresh (less than 24 hours old)
    const MAX_DATA_AGE_HOURS = 24;
    const soilIsFresh = soilAgeHours !== null && soilAgeHours < MAX_DATA_AGE_HOURS;
    const imageIsFresh = imageAgeHours !== null && imageAgeHours < MAX_DATA_AGE_HOURS;
    
    // Determine data status
    const soilStatus = !latestSoil ? 'missing' : 
                      !soilIsFresh ? 'stale' : 'fresh';
                      
    const imageStatus = !latestImage ? 'missing' : 
                       !imageIsFresh ? 'stale' : 'fresh';
    
    // FIXED: Ensure these are boolean values, not objects
    const canAnalyze = !!latestSoil && !!latestImage; // Convert to boolean
    const canAnalyzeOptimal = !!latestSoil && !!latestImage && soilIsFresh && imageIsFresh;
    
    const response = {
      success: true,
      can_analyze: canAnalyze, // This should be boolean true/false
      can_analyze_optimal: canAnalyzeOptimal, // This should be boolean true/false
      soil_data: {
        exists: !!latestSoil,
        status: soilStatus,
        age_hours: soilAgeHours ? Math.round(soilAgeHours * 10) / 10 : null,
        is_fresh: soilIsFresh,
        last_reading: latestSoil?.timestamp || null,
        data: latestSoil // Include the actual soil data for debugging
      },
      image_data: {
        exists: !!latestImage,
        status: imageStatus,
        age_hours: imageAgeHours ? Math.round(imageAgeHours * 10) / 10 : null,
        is_fresh: imageIsFresh,
        last_capture: latestImage?.timestamp || null,
        data: latestImage // Include the actual image data for debugging
      },
      requirements: {
        max_data_age_hours: MAX_DATA_AGE_HOURS,
        needed: ['soil_measurements', 'plant_image'],
        message: canAnalyzeOptimal ? 
          '✅ All data is fresh and ready for optimal analysis' :
          canAnalyze ? 
          '⚠️ Data available but may be outdated. Analysis can proceed.' :
          '❌ Need both soil data and plant image for analysis'
      },
      user_id: userId,
      timestamp: now.toISOString()
    };
    
    console.log('✅ Data status check completed:', {
      canAnalyze: response.can_analyze, // Log the actual boolean value
      canAnalyzeOptimal: response.can_analyze_optimal,
      soilStatus,
      imageStatus
    });
    
    res.json(response);
    
  } catch (error) {
    console.error('❌ Data status check failed:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to check data status: ' + error.message,
      error: process.env.NODE_ENV === 'development' ? error.stack : undefined
    });
  }
});

// Perform integrated analysis (image identification + soil data) - MODIFIED to work with any data
router.post('/integrated', async (req, res) => {
  try {
    const { userId, imageData, soilData } = req.body;
    
    if (!userId) {
      return res.status(400).json({
        success: false,
        message: 'User ID is required'
      });
    }
    
    console.log(`🔍 Starting integrated analysis for user ${userId}...`);
    
    let latestSoil, latestImage;

    // Use provided soil data or fetch latest
    if (soilData) {
      latestSoil = soilData;
      console.log('✅ Using provided soil data');
    } else {
      latestSoil = await storageService.getLatestSoilData(userId);
      console.log('Latest soil data:', latestSoil ? 'found' : 'not found');
    }

    // Use provided image data or fetch latest
    if (imageData) {
      latestImage = imageData;
      console.log('✅ Using provided image data');
    } else {
      latestImage = await storageService.getLatestImage(userId);
      console.log('Latest image:', latestImage ? 'found' : 'not found');
    }

    if (!latestImage) {
      return res.status(404).json({
        success: false,
        message: 'No plant image found in database. Please capture a plant image first.'
      });
    }

    if (!latestSoil) {
      return res.status(404).json({
        success: false,
        message: 'No soil data found in database. Please add soil measurements first.'
      });
    }

    // Check ML service status
    const mlHealth = mlService.healthCheck();
    console.log('🤖 ML Service status:', mlHealth.initialized ? 'TFLite ready' : 'Fallback mode');

    // Perform ML analysis on image
    console.log('🤖 Performing image analysis...');
    const imageAnalysis = await mlService.analyzeImage(latestImage);
    console.log('Image analysis result:', {
      disease: imageAnalysis.disease,
      confidence: imageAnalysis.confidence,
      model: imageAnalysis.model_used
    });
    
    // Combine image analysis with soil data for recommendations
    console.log('🔗 Performing integrated analysis...');
    const integratedAnalysis = await mlService.integratedAnalysis(imageAnalysis, latestSoil);

    // Store results
    let analysisId = null;
    const analysisResult = {
      disease_type: integratedAnalysis.diseaseType,
      confidence: integratedAnalysis.confidence,
      plant_type: integratedAnalysis.plantType,
      severity: integratedAnalysis.severity,
      soil_health: integratedAnalysis.soilHealth,
      health_score: integratedAnalysis.healthScore,
      overall_health: integratedAnalysis.overallHealth,
      recommendations: integratedAnalysis.recommendations,
      model_used: integratedAnalysis.modelUsed,
      inference_time: integratedAnalysis.inferenceTime,
      user_id: userId,
      timestamp: integratedAnalysis.timestamp,
      data_freshness: {
        soil_age_hours: latestSoil.timestamp ? (new Date() - new Date(latestSoil.timestamp)) / (1000 * 60 * 60) : null,
        image_age_hours: latestImage.timestamp ? (new Date() - new Date(latestImage.timestamp)) / (1000 * 60 * 60) : null
      }
    };

    console.log('💾 Storing analysis results...');
    analysisId = await storageService.storeAnalysisResult(userId, analysisResult);

    console.log(`✅ Integrated analysis completed!`);
    
    res.json({
      success: true,
      message: 'Integrated analysis completed successfully',
      analysis_id: analysisId,
      user_id: userId,
      data_used: {
        soil_timestamp: latestSoil.timestamp,
        image_timestamp: latestImage.timestamp
      },
      ...integratedAnalysis
    });

  } catch (error) {
    console.error('❌ Analysis error:', error);
    res.status(500).json({
      success: false,
      message: 'Analysis failed: ' + error.message,
      error: process.env.NODE_ENV === 'development' ? error.stack : undefined
    });
  }
});

// Quick image analysis only (without soil data)
router.post('/analyze-image', async (req, res) => {
  try {
    const { userId, imageData } = req.body;
    
    if (!userId) {
      return res.status(400).json({
        success: false,
        message: 'User ID is required'
      });
    }

    if (!imageData) {
      return res.status(400).json({
        success: false,
        message: 'Image data is required'
      });
    }

    console.log(`🤖 Performing image-only analysis for user ${userId}...`);

    // Perform ML analysis on image
    const imageAnalysis = await mlService.analyzeImage(imageData);
    
    console.log('✅ Image analysis completed:', {
      disease: imageAnalysis.disease,
      confidence: imageAnalysis.confidence
    });
    
    res.json({
      success: true,
      message: 'Image analysis completed successfully',
      ...imageAnalysis,
      user_id: userId,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ Image analysis error:', error);
    res.status(500).json({
      success: false,
      message: 'Image analysis failed: ' + error.message
    });
  }
});

// Get analysis history
router.get('/history', async (req, res) => {
  try {
    const userId = req.query.userId;
    
    if (!userId) {
      return res.status(400).json({
        success: false,
        message: 'User ID is required'
      });
    }
    
    const limit = parseInt(req.query.limit) || 10;
    console.log(`📚 Fetching analysis history for user ${userId}, limit: ${limit}`);
    
    const history = await storageService.getAnalysisHistory(userId, limit);

    res.json({
      success: true,
      history: history,
      count: history.length,
      user_id: userId,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ Error fetching analysis history:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch analysis history: ' + error.message
    });
  }
});

// Get specific analysis by ID
router.get('/:analysisId', async (req, res) => {
  try {
    const userId = req.query.userId;
    const { analysisId } = req.params;
    
    if (!userId) {
      return res.status(400).json({
        success: false,
        message: 'User ID is required'
      });
    }
    
    console.log(`📄 Fetching analysis ${analysisId} for user ${userId}`);
    
    const history = await storageService.getAnalysisHistory(userId, 50);
    const analysis = history.find(item => item.id === analysisId);
    
    if (!analysis) {
      return res.status(404).json({
        success: false,
        message: 'Analysis not found'
      });
    }

    res.json({
      success: true,
      analysis: analysis,
      user_id: userId
    });
  } catch (error) {
    console.error('❌ Error fetching analysis:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch analysis: ' + error.message
    });
  }
});

// Get analysis statistics
router.get('/stats/summary', async (req, res) => {
  try {
    const userId = req.query.userId;
    
    if (!userId) {
      return res.status(400).json({
        success: false,
        message: 'User ID is required'
      });
    }
    
    console.log(`📈 Fetching analysis statistics for user ${userId}`);
    
    const history = await storageService.getAnalysisHistory(userId, 100);
    
    const stats = {
      total_analyses: history.length,
      average_health_score: history.length > 0 ? 
        Math.round(history.reduce((sum, item) => sum + item.health_score, 0) / history.length) : 0,
      disease_distribution: calculateDiseaseDistribution(history),
      recent_trend: calculateHealthTrend(history),
      best_score: history.length > 0 ? Math.max(...history.map(item => item.health_score)) : 0,
      worst_score: history.length > 0 ? Math.min(...history.map(item => item.health_score)) : 0
    };

    res.json({
      success: true,
      statistics: stats,
      user_id: userId,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ Error fetching analysis statistics:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch analysis statistics: ' + error.message
    });
  }
});

// Health check for analysis service
router.get('/health/status', async (req, res) => {
  try {
    const userId = req.query.userId;
    
    if (!userId) {
      return res.status(400).json({
        success: false,
        message: 'User ID is required'
      });
    }
    
    const storageHealth = await storageService.healthCheck();
    const mlHealth = mlService.healthCheck();
    const history = await storageService.getAnalysisHistory(userId, 1);
    
    res.json({
      success: true,
      health: {
        storage: storageHealth,
        ml_service: {
          status: mlHealth.initialized ? 'tflite_ready' : 'fallback_mode',
          model_loaded: mlHealth.model_loaded,
          using_tflite: mlHealth.initialized,
          runtime: mlHealth.runtime
        },
        last_analysis: history.length > 0 ? history[0].timestamp : 'No analyses yet',
        total_analyses: (await storageService.getAnalysisHistory(userId, 100)).length
      },
      user_id: userId,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ Error in analysis health check:', error);
    res.status(500).json({
      success: false,
      message: 'Analysis health check failed: ' + error.message
    });
  }
});

// Helper function to calculate disease distribution
function calculateDiseaseDistribution(history) {
  const distribution = {};
  history.forEach(item => {
    const disease = item.disease_type || 'Unknown';
    distribution[disease] = (distribution[disease] || 0) + 1;
  });
  return distribution;
}

// Helper function to calculate health trend
function calculateHealthTrend(history) {
  if (history.length < 2) return 'insufficient_data';
  
  const recent = history.slice(0, 5); // Last 5 analyses
  const scores = recent.map(item => item.health_score);
  
  if (scores.length < 2) return 'stable';
  
  const first = scores[0];
  const last = scores[scores.length - 1];
  
  if (last > first + 5) return 'improving';
  if (last < first - 5) return 'declining';
  return 'stable';
}

module.exports = router;