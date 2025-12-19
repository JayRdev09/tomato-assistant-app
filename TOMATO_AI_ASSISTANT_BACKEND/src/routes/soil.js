const express = require('express');
const router = express.Router();
const storageService = require('../services/storageService');

// Middleware to validate userId
const validateUserId = (req, res, next) => {
  const userId = req.body.userId || req.query.userId;
  
  if (!userId) {
    return res.status(400).json({
      success: false,
      message: 'User ID is required'
    });
  }
  
  next();
};

// Enhanced soil status endpoint (READ ONLY)
router.get('/status', validateUserId, async (req, res) => {
  try {
    const userId = req.query.userId;
    
    console.log('📊 Fetching enhanced soil status for user:', userId);
    const soilData = await storageService.getLatestSoilData(userId);

    const now = new Date();
    let dataStatus = 'no_data';
    let dataAgeHours = null;
    let dataFreshness = 'unknown';

    if (soilData && soilData.date_gathered) {
      const soilTime = new Date(soilData.date_gathered);
      dataAgeHours = (now - soilTime) / (1000 * 60 * 60);
      
      // Determine freshness
      if (dataAgeHours <= 1) {
        dataFreshness = 'very_fresh';
        dataStatus = 'fresh';
      } else if (dataAgeHours <= 6) {
        dataFreshness = 'fresh';
        dataStatus = 'fresh';
      } else if (dataAgeHours <= 24) {
        dataFreshness = 'acceptable';
        dataStatus = 'fresh';
      } else {
        dataFreshness = 'stale';
        dataStatus = 'stale';
      }
    }

    if (!soilData) {
      console.log('No soil data found for user:', userId, 'returning enhanced defaults');
      return res.json({
        success: true,
        npk_levels: {
          nitrogen: '0.0 mg/kg',
          phosphorus: '0.0 mg/kg', 
          potassium: '0.0 mg/kg'
        },
        other_parameters: {
          ph: '0.0 pH',
          moisture: '0.0%',
          temperature: '0.0°C'
        },
        data_status: 'no_data',
        data_age_hours: null,
        data_freshness: 'no_data',
        last_updated: null,
        can_analyze: false,
        message: 'No soil data available.',
        user_id: userId
      });
    }

    console.log('Enhanced soil data found for user:', userId, {
      data_status: dataStatus,
      age_hours: dataAgeHours?.toFixed(1),
      freshness: dataFreshness
    });
    
    res.json({
      success: true,
      npk_levels: {
        nitrogen: `${soilData.nitrogen || 0}mg/kg`,
        phosphorus: `${soilData.phosphorus || 0}mg/kg`,
        potassium: `${soilData.potassium || 0}mg/kg`
      },
      other_parameters: {
        ph: `${(soilData.ph_level || soilData.ph || 0).toFixed(1)} pH`,
        moisture: `${soilData.moisture || soilData.moisture || 0}%`,
        temperature: `${soilData.temperature || 0}°C`
      },
      data_status: dataStatus,
      data_age_hours: dataAgeHours ? parseFloat(dataAgeHours.toFixed(1)) : null,
      data_freshness: dataFreshness,
      last_updated: soilData.date_gathered || soilData.timestamp,
      can_analyze: dataStatus === 'fresh',
      message: dataStatus === 'fresh' ? 
        'Soil data is current and ready for analysis' :
        dataStatus === 'stale' ? 
          `Soil data is ${dataAgeHours?.toFixed(1)} hours old.` :
          'No soil data available',
      user_id: userId
    });
  } catch (error) {
    console.error('❌ Error fetching enhanced soil status:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch soil status: ' + error.message
    });
  }
});

// Get soil data history
router.get('/history', validateUserId, async (req, res) => {
  try {
    const userId = req.query.userId;
    const limit = parseInt(req.query.limit) || 10;
    
    console.log('📚 Fetching soil data history for user:', userId, 'limit:', limit);
    
    const analysisHistory = await storageService.getAnalysisHistory(userId, limit);
    
    const soilHistory = analysisHistory
      .filter(analysis => analysis.soil_data)
      .map(analysis => ({
        soil_id: analysis.soil_id,
        ...analysis.soil_data,
        date_gathered: analysis.soil_data.date_gathered,
        analysis_date: analysis.date_predicted
      }));

    res.json({
      success: true,
      soil_history: soilHistory,
      count: soilHistory.length,
      user_id: userId
    });
  } catch (error) {
    console.error('❌ Error fetching soil history:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch soil history: ' + error.message
    });
  }
});

// Get soil statistics
router.get('/stats', validateUserId, async (req, res) => {
  try {
    const userId = req.query.userId;
    
    console.log('📈 Fetching soil statistics for user:', userId);
    
    const soilData = await storageService.getLatestSoilData(userId);
    const analysisHistory = await storageService.getAnalysisHistory(userId, 50);
    
    const soilEntries = analysisHistory
      .filter(analysis => analysis.soil_data)
      .map(analysis => analysis.soil_data);

    const stats = {
      total_entries: soilEntries.length,
      average_nitrogen: 0,
      average_phosphorus: 0,
      average_potassium: 0,
      average_ph: 0,
      average_temperature: 0,
      average_moisture: 0
    };

    if (soilEntries.length > 0) {
      stats.average_nitrogen = (soilEntries.reduce((sum, entry) => sum + (entry.nitrogen || 0), 0) / soilEntries.length).toFixed(2);
      stats.average_phosphorus = (soilEntries.reduce((sum, entry) => sum + (entry.phosphorus || 0), 0) / soilEntries.length).toFixed(2);
      stats.average_potassium = (soilEntries.reduce((sum, entry) => sum + (entry.potassium || 0), 0) / soilEntries.length).toFixed(2);
      stats.average_ph = (soilEntries.reduce((sum, entry) => sum + (entry.ph_level || entry.ph || 0), 0) / soilEntries.length).toFixed(2);
      stats.average_temperature = (soilEntries.reduce((sum, entry) => sum + (entry.temperature || 0), 0) / soilEntries.length).toFixed(2);
      stats.average_moisture = (soilEntries.reduce((sum, entry) => sum + (entry.moisture || entry.moisture || 0), 0) / soilEntries.length).toFixed(2);
    }

    res.json({
      success: true,
      statistics: stats,
      user_id: userId,
      last_update: soilData?.date_gathered || null
    });
  } catch (error) {
    console.error('❌ Error fetching soil statistics:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch soil statistics: ' + error.message
    });
  }
});

module.exports = router;