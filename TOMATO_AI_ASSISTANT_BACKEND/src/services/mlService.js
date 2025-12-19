const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const supabaseService = require('./supabaseService');
const LateFusionService = require('./lateFusionService');
const https = require('https');

class MLService {
  constructor() {
    this.initialized = false;
    this.model_loaded = false;
    this.runtime = 'nodejs';
    this.supports_tflite = false;
    this.class_count = 0;
    this.pythonScriptsPath = path.join(__dirname, '..', '..', 'python_scripts');
    this.tempDir = path.join(__dirname, '..', '..', 'temp');
    this.lateFusionService = new LateFusionService();
    
    this.supabase = supabaseService;
    if (!fs.existsSync(this.tempDir)) {
      fs.mkdirSync(this.tempDir, { recursive: true });
    }
  }

  async initialize() {
    try {
      console.log('🤖 Initializing ML Service...');
      
      const pythonCheck = await this.checkPythonEnvironment();
      if (!pythonCheck.available) {
        console.warn('⚠️ Python environment not available, using fallback mode');
        this.initialized = true;
        this.model_loaded = false;
        return;
      }

      console.log('✅ Python environment ready');
      this.initialized = true;
      this.model_loaded = true;
      this.class_count = 6;
      
      console.log('✅ ML Service initialized successfully');
    } catch (error) {
      console.error('❌ ML Service initialization failed:', error);
      this.initialized = true;
      this.model_loaded = false;
    }
  }

  async checkPythonEnvironment() {
    return new Promise((resolve) => {
      const python = spawn('python', ['-c', `
import sys
try:
    import tensorflow as tf
    import numpy as np
    import cv2
    import joblib
    import pandas as pd
    from PIL import Image
    print("SUCCESS:All dependencies available")
except ImportError as e:
    print(f"ERROR:{e}")
      `]);

      let output = '';
      python.stdout.on('data', (data) => {
        output += data.toString();
      });

      python.on('close', (code) => {
        if (code === 0 && output.includes('SUCCESS')) {
          resolve({ available: true });
        } else {
          resolve({ available: false, error: output });
        }
      });
    });
  }

  async analyzeImage(imageData, userId, imageId) {
    try {
      console.log('🤖 Starting image analysis for disease identification...');
      
      if (!this.initialized) {
        throw new Error('ML Service not initialized');
      }

      let imagePath = await this.getImageLocalPath(imageData);
      
      if (!imagePath || !fs.existsSync(imagePath)) {
        throw new Error(`Image file not found: ${imagePath}`);
      }

      console.log('📁 Processing image:', imagePath);

      const classificationResult = await this.executeTomatoClassifier(imagePath, userId, imageId);
      
      if (imagePath.includes(this.tempDir)) {
        this.cleanupTempFile(imagePath);
      }

      if (!classificationResult.success) {
        throw new Error(classificationResult.error || 'Image classification failed');
      }

      console.log('✅ Image analysis completed:', {
        disease: classificationResult.disease_type,
        confidence: classificationResult.confidence_score,
        health_status: classificationResult.health_status
      });

      return {
        success: true,
        tomato_type: classificationResult.tomato_type,
        health_status: classificationResult.health_status,
        disease_type: classificationResult.disease_type,
        confidence_score: classificationResult.confidence_score,
        plant_health_score: classificationResult.plant_health_score,
        recommendations: classificationResult.recommendations || [],
        
        disease: classificationResult.disease_type,
        confidence: classificationResult.confidence_score,
        
        is_tomato: classificationResult.is_tomato,
        top_predictions: classificationResult.top_predictions,
        features: classificationResult.features,
        model_used: classificationResult.model_used,
        inference_time: classificationResult.inference_time,
        timestamp: new Date().toISOString(),
        user_id: userId,
        image_id: imageId
      };

    } catch (error) {
      console.error('❌ Image analysis failed:', error);
      return this.getImageFallbackAnalysis(error.message);
    }
  }

  async analyzeBatchImages(imageDataList, userId) {
    try {
        console.log(`🤖 Processing batch of ${imageDataList.length} images for user ${userId}`);
        
        const results = [];
        let successful_predictions = 0;
        let failed_predictions = 0;
        
        for (let i = 0; i < imageDataList.length; i++) {
            try {
                const imageData = imageDataList[i];
                console.log(`🖼️ Processing batch image ${i + 1}/${imageDataList.length}`);
                
                // Use single image analysis for each image in the batch
                const imageResult = await this.analyzeImage(imageData, userId, imageData.image_id || `batch_${userId}_${Date.now()}_${i}`);
                
                if (imageResult.success) {
                    successful_predictions++;
                    
                    // Ensure the result has all required fields
                    const structuredResult = {
                        success: true,
                        image_id: imageData.image_id,
                        tomato_type: imageResult.tomato_type || 'Unknown',
                        health_status: imageResult.health_status || 'Unknown',
                        disease_type: imageResult.disease_type || 'Unknown',
                        confidence_score: imageResult.confidence_score || 0.5,
                        plant_health_score: imageResult.plant_health_score !== undefined ? imageResult.plant_health_score : null,
                        recommendations: imageResult.recommendations || [],
                        overall_health: imageResult.overall_health || imageResult.health_status || 'Unknown',
                        batch_index: i
                    };
                    
                    results.push(structuredResult);
                } else {
                    failed_predictions++;
                    results.push({
                        success: false,
                        image_id: imageData.image_id,
                        error: imageResult.error || 'Unknown error',
                        batch_index: i
                    });
                }
            } catch (error) {
                console.error(`❌ Error processing batch image ${i + 1}:`, error.message);
                failed_predictions++;
                results.push({
                    success: false,
                    image_id: imageDataList[i]?.image_id,
                    error: error.message,
                    batch_index: i
                });
            }
        }
        
        console.log(`✅ Batch image analysis completed: ${successful_predictions} successful, ${failed_predictions} failed`);
        
        return {
            success: true,
            successful_predictions,
            failed_predictions,
            results,
            total_images: imageDataList.length
        };
        
    } catch (error) {
        console.error('❌ Batch image analysis failed:', error);
        return {
            success: false,
            error: error.message,
            successful_predictions: 0,
            failed_predictions: imageDataList.length,
            results: []
        };
    }
}

  async getImageLocalPath(imageData) {
    if (typeof imageData === 'string' && fs.existsSync(imageData)) {
      return imageData;
    }

    if (imageData.publicUrl) {
      return await this.downloadImageFromUrl(imageData.publicUrl);
    }

    if (imageData.image_path) {
      const publicUrl = await this.getImagePublicUrl(imageData.image_path);
      if (publicUrl) {
        return await this.downloadImageFromUrl(publicUrl);
      }
    }

    throw new Error('Cannot resolve image to local path');
  }

  async getImagePublicUrl(filePath) {
    try {
      const supabaseUrl = process.env.SUPABASE_URL;
      if (!supabaseUrl) {
        throw new Error('SUPABASE_URL environment variable not set');
      }

      const cleanFilePath = filePath.replace(/^\//, '');
      const publicUrl = `${supabaseUrl}/storage/v1/object/public/images/${cleanFilePath}`;
      console.log('🔗 Constructed public URL:', publicUrl);
      
      return publicUrl;
    } catch (error) {
      console.error('❌ Error constructing public URL:', error);
      return null;
    }
  }

  async downloadImageFromUrl(imageUrl) {
    return new Promise((resolve, reject) => {
      const filename = `temp_image_${Date.now()}.jpg`;
      const filePath = path.join(this.tempDir, filename);
      
      console.log('📥 Downloading image to:', filePath);
      
      const file = fs.createWriteStream(filePath);
      
      https.get(imageUrl, (response) => {
        if (response.statusCode !== 200) {
          reject(new Error(`Failed to download image: HTTP ${response.statusCode}`));
          return;
        }

        response.pipe(file);
        
        file.on('finish', () => {
          file.close();
          console.log('✅ Image downloaded successfully');
          resolve(filePath);
        });
      }).on('error', (err) => {
        fs.unlink(filePath, () => {});
        reject(new Error(`Failed to download image: ${err.message}`));
      });
    });
  }

  async executeTomatoClassifier(imagePath, userId, imageId) {
    return new Promise((resolve) => {
      const pythonScript = path.join(this.pythonScriptsPath, 'tomato_prediction.py');
      
      console.log('🔍 Running tomato classifier for disease identification...');

      const inputData = {
        image_path: imagePath,
        user_id: userId,
        image_id: imageId
      };

      const env = { 
        ...process.env, 
        TF_ENABLE_ONEDNN_OPTS: '0',
        PYTHONIOENCODING: 'utf-8'
      };
      
      const python = spawn('python', [pythonScript, JSON.stringify(inputData)], { 
        env
      });
      
      let output = '';
      let errorOutput = '';

      python.stdout.on('data', (data) => {
        output += data.toString('utf8');
      });

      python.stderr.on('data', (data) => {
        const errorData = data.toString('utf8');
        errorOutput += errorData;
        console.error('🐍 Python stderr:', errorData.trim());
      });

      python.on('close', (code) => {
        console.log(`🐍 Tomato classifier exited with code ${code}`);
        
        if (code === 0) {
          try {
            let result;
            try {
              result = JSON.parse(output);
            } catch (parseError) {
              const jsonMatch = output.match(/\{.*\}/s);
              if (jsonMatch) {
                result = JSON.parse(jsonMatch[0]);
              } else {
                throw new Error('No valid JSON found in output');
              }
            }
            
            resolve(result);
          } catch (parseError) {
            console.error('❌ Failed to parse Python output:', parseError);
            console.error('Raw output:', output);
            resolve({
              success: false,
              error: `Failed to parse Python output: ${parseError.message}`
            });
          }
        } else {
          console.error('❌ Python script failed with error:', errorOutput);
          resolve({
            success: false,
            error: `Python script failed with code ${code}: ${errorOutput}`
          });
        }
      });

      python.on('error', (error) => {
        console.error('❌ Failed to start Python process:', error);
        resolve({
          success: false,
          error: `Failed to start Python process: ${error.message}`
        });
      });

      setTimeout(() => {
        if (!python.killed) {
          python.kill();
          resolve({
            success: false,
            error: 'Image analysis timeout'
          });
        }
      }, 60000);
    });
  }

  async analyzeSoil(soilData, userId, soilId) {
    try {
      console.log('🌱 Starting soil analysis...');
      
      if (!this.initialized) {
        throw new Error('ML Service not initialized');
      }

      console.log('📊 Soil data to analyze:', soilData);
      console.log('📊 Soil data keys:', Object.keys(soilData));

      // Try to fetch optimal ranges from database
      let optimalRanges;
      try {
        optimalRanges = await this.fetchOptimalRanges();
        console.log('📊 Optimal ranges fetched from database:', Object.keys(optimalRanges));
      } catch (dbError) {
        console.error('❌ Database fetch failed, using fallback ranges:', dbError.message);
        // If database fails, use fallback
        optimalRanges = this.getDefaultOptimalRanges();
      }

      const soilResult = await this.executeSoilPrediction(soilData, optimalRanges, userId, soilId);
      
      if (!soilResult.success) {
        throw new Error(soilResult.error || 'Soil analysis failed');  
      }

      console.log('✅ Soil analysis completed:', {
        soil_status: soilResult.soil_status,
      health_score: soilResult.soil_quality_score, // CHANGED: Use soil_quality_score instead of soil_health_score
        soil_issues_count: soilResult.soil_issues?.length || 0
      });

      return {
        success: true,
        soil_status: soilResult.soil_status,
        confidence_score: soilResult.confidence_score,
        soil_issues: soilResult.soil_issues || [],
        recommendations: soilResult.recommendations || [],
         soil_quality_score: soilResult.soil_quality_score, // This is the correct field from Python
        parameter_scores: soilResult.parameter_scores,
        soil_parameters: soilResult.soil_parameters,
        model_used: soilResult.model_used,
        inference_time: soilResult.inference_time,
        timestamp: new Date().toISOString(),
        user_id: userId,
        soil_id: soilId
      };

    } catch (error) {
      console.error('❌ Soil analysis failed:', error);
      return this.getSoilFallbackAnalysis(error.message);
    }
  }

  async executeSoilPrediction(soilData, optimalRanges, userId, soilId) {
    return new Promise((resolve) => {
      const pythonScript = path.join(this.pythonScriptsPath, 'soil_prediction.py');
      
      console.log('🔍 Running soil prediction...');
      
      const requiredSoilFields = ['ph_level', 'temperature', 'moisture', 'nitrogen', 'phosphorus', 'potassium'];
      const filteredSoilData = {};
      
      for (const field of requiredSoilFields) {
        if (field in soilData) {
          filteredSoilData[field] = soilData[field];
        } else {
          console.error(`❌ Missing required soil field: ${field}`);
          resolve({
            success: false,
            error: `Missing required soil field: ${field}`
          });
          return;
        }
      }
      
      console.log('📊 Filtered soil data (6 fields):', filteredSoilData);
      console.log('📊 Optimal ranges to send:', optimalRanges);

      const inputData = {
        soil_data: filteredSoilData,
        optimal_ranges: optimalRanges,
        user_id: userId,
        soil_id: soilId
      };

      console.log('📤 Full input to Python:', JSON.stringify(inputData, null, 2));

      const env = { 
        ...process.env, 
        PYTHONIOENCODING: 'utf-8'
      };

      const python = spawn('python', [pythonScript, JSON.stringify(inputData)], { 
        env
      });
      
      let output = '';
      let errorOutput = '';

      python.stdout.on('data', (data) => {
        output += data.toString('utf8');
      });

      python.stderr.on('data', (data) => {
        const errorData = data.toString('utf8');
        errorOutput += errorData;
        console.error('🐍 Python stderr:', errorData.trim());
      });

      python.on('close', (code) => {
        console.log(`🐍 Soil prediction exited with code ${code}`);
        
        if (code === 0) {
          try {
            let result;
            try {
              result = JSON.parse(output);
            } catch (parseError) {
              const jsonMatch = output.match(/\{.*\}/s);
              if (jsonMatch) {
                result = JSON.parse(jsonMatch[0]);
              } else {
                throw new Error('No valid JSON found in output');
              }
            }
            
            resolve(result);
          } catch (parseError) {
            console.error('❌ Failed to parse soil analysis output:', parseError);
            console.error('Raw output:', output);
            resolve({
              success: false,
              error: `Failed to parse soil analysis output: ${parseError.message}`
            });
          }
        } else {
          console.error('❌ Python error output:', errorOutput);
          resolve({
            success: false,
            error: `Soil analysis failed: ${errorOutput}`
          });
        }
      });

      python.on('error', (error) => {
        console.error('❌ Failed to start Python process:', error);
        resolve({
          success: false,
          error: `Failed to start Python process: ${error.message}`
        });
      });

      setTimeout(() => {
        if (!python.killed) {
          python.kill();
          resolve({
            success: false,
            error: 'Soil analysis timeout'
          });
        }
      }, 60000);
    });
  }

  async fetchOptimalRanges() {
    try {
      console.log('📊 Fetching optimal ranges from Supabase...');
      
      // Get the Supabase client - check if it's a function or property
      let supabaseClient;
      if (typeof this.supabase === 'function') {
        supabaseClient = this.supabase();
      } else if (this.supabase.client) {
        supabaseClient = this.supabase.client;
      } else {
        supabaseClient = this.supabase;
      }
      
      if (!supabaseClient || !supabaseClient.from) {
        console.error('❌ Supabase client not properly initialized');
        throw new Error('Supabase client not available');
      }

      console.log('🔍 Querying optimal_ranges table...');
      
      const { data, error } = await supabaseClient
        .from('optimal_ranges')
        .select('parameter, optimal_min, optimal_max, unit')
        .eq('crop_type', 'tomato');
      
      if (error) {
        console.error('❌ Database query error:', error.message);
        throw error;
      }
      
      if (!data || data.length === 0) {
        console.error('❌ No optimal ranges found in database');
        throw new Error('No optimal ranges found in database');
      }
      
      console.log(`✅ Found ${data.length} optimal ranges in database`);
      
      const optimalRanges = {};
      
      data.forEach(row => {
        optimalRanges[row.parameter] = {
          optimal: [parseFloat(row.optimal_min), parseFloat(row.optimal_max)],
          unit: row.unit || ''
        };
      });
      
      console.log('✅ Fetched optimal ranges:', Object.keys(optimalRanges));
      return optimalRanges;
      
    } catch (error) {
      console.error('❌ Failed to fetch optimal ranges:', error.message);
      throw error;
    }
  }

  getDefaultOptimalRanges() {
    return {
      ph_level: { optimal: [6.0, 7.0], unit: 'pH' },
      temperature: { optimal: [20, 30], unit: '°C' },
      moisture: { optimal: [60, 80], unit: '%' },
      nitrogen: { optimal: [40, 60], unit: 'mg/kg' },
      phosphorus: { optimal: [30, 50], unit: 'mg/kg' },
      potassium: { optimal: [40, 60], unit: 'mg/kg' }
    };
  }

  async integratedAnalysis(imageAnalysis, soilAnalysis, userId, imageId, soilId) {
    try {
      console.log('🔗 Starting integrated analysis...');

      if (!imageAnalysis.success) {
        throw new Error('Image analysis failed: ' + imageAnalysis.error);
      }

      if (!soilAnalysis.success) {
        throw new Error('Soil analysis failed: ' + soilAnalysis.error);
      }

      console.log('🔍 Raw image analysis fields:', {
        disease_type: imageAnalysis.disease_type,
        confidence_score: imageAnalysis.confidence_score,
        recommendations: imageAnalysis.recommendations,
        tomato_type: imageAnalysis.tomato_type,
        health_status: imageAnalysis.health_status,
        plant_health_score: imageAnalysis.plant_health_score
      });

      console.log('🔍 Raw soil analysis fields:', {
        soil_status: soilAnalysis.soil_status,
        soil_quality_score: soilAnalysis.soil_quality_score,
        confidence_score: soilAnalysis.confidence_score,
        soil_issues: soilAnalysis.soil_issues,
        recommendations: soilAnalysis.recommendations
      });

      const structuredImageAnalysis = imageAnalysis;
      const structuredSoilAnalysis = soilAnalysis;

      console.log('🔍 Structured analysis ready for fusion:');
      console.log('  - Image:', {
        tomato_type: structuredImageAnalysis.tomato_type,
        health_status: structuredImageAnalysis.health_status,
        disease_type: structuredImageAnalysis.disease_type,
        confidence_score: structuredImageAnalysis.confidence_score,
        plant_health_score: structuredImageAnalysis.plant_health_score,
        recommendations_count: structuredImageAnalysis.recommendations?.length || 0
      });
      console.log('  - Soil:', {
        soil_status: structuredSoilAnalysis.soil_status,
        soil_quality_score: structuredSoilAnalysis.soil_quality_score,
        confidence_score: structuredSoilAnalysis.confidence_score,
        soil_issues_count: structuredSoilAnalysis.soil_issues?.length || 0,
        recommendations_count: structuredSoilAnalysis.recommendations?.length || 0
      });

      console.log('🔄 Performing late fusion of image and soil analyses...');
      const fusedResult = await this.lateFusionService.performLateFusion(
        structuredImageAnalysis, 
        structuredSoilAnalysis, 
        userId, 
        imageId, 
        soilId
      );

      console.log('✅ Integrated analysis completed');
      
      return {
        success: true,
        prediction_id: fusedResult.prediction_id,
        diseaseType: fusedResult.disease_type,
        confidence: parseFloat(fusedResult.combined_confidence_score) || 0,
        plantType: fusedResult.tomato_type,
        soilHealth: fusedResult.soil_status,
        healthScore: this.calculateHealthScore(fusedResult.overall_health),
        overallHealth: fusedResult.overall_health,
        recommendations: fusedResult.recommendations?.split('; ') || [],
        soilIssues: fusedResult.soil_issues?.split('; ') || [],
        modelUsed: 'late_fusion',
        inferenceTime: (imageAnalysis.inference_time || 0) + (soilAnalysis.inference_time || 0),
        timestamp: fusedResult.date_predicted,
        user_id: userId,
        image_id: imageId,
        soil_id: soilId
      };

    } catch (error) {
      console.error('❌ Integrated analysis failed:', error);
      return this.getIntegratedFallbackAnalysis(imageAnalysis, soilAnalysis, error.message);
    }
  }

  calculateHealthScore(overallHealth) {
    const scores = {
      'Excellent': 90,
      'Good': 75,
      'Average': 60,
      'Needs Attention': 40,
      'Critical': 20,
      'Unknown': 50
    };
    return scores[overallHealth] || 50;
  }

  cleanupTempFile(filePath) {
    try {
      if (filePath && filePath.startsWith(this.tempDir)) {
        fs.unlink(filePath, (err) => {
          if (!err) {
            console.log('🧹 Cleaned up temp file');
          }
        });
      }
    } catch (error) {
      // Ignore cleanup errors
    }
  }

  getImageFallbackAnalysis(error) {
    return {
      success: false,
      tomato_type: 'Unknown',
      health_status: 'Unknown',
      disease_type: 'Unknown',
      confidence_score: 0,
      plant_health_score: 0,
      recommendations: [],
      
      disease: 'Unknown',
      confidence: 0,
      
      is_tomato: false,
      top_predictions: [],
      features: [],
      model_used: 'fallback',
      inference_time: 0,
      error: error,
      timestamp: new Date().toISOString()
    };
  }

  getSoilFallbackAnalysis(error) {
    return {
      success: false,
      soil_status: 'Unknown',
      soil_health_score: 0,
      confidence_score: 0,
      soil_issues: ['Analysis failed'],
      recommendations: ['Check system configuration'],
      
      soil_quality_score: 0,
      parameter_scores: {},
      soil_parameters: {},
      
      model_used: 'fallback',
      inference_time: 0,
      error: error,
      timestamp: new Date().toISOString()
    };
  }

 

  healthCheck() {
    return {
      initialized: this.initialized,
      model_loaded: this.model_loaded,
      runtime: this.runtime,
      supports_tflite: this.supports_tflite,
      class_count: this.class_count,
      timestamp: new Date().toISOString()
    };
  }
}

module.exports = new MLService();