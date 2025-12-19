import pandas as pd
import joblib
import numpy as np
import warnings
import json
import sys
import os
import logging
import time

# Configure logging to output to stderr
logging.basicConfig(level=logging.INFO, format='%(message)s', stream=sys.stderr)
sys.stdout.reconfigure(encoding='utf-8') if hasattr(sys.stdout, 'reconfigure') else None
warnings.filterwarnings("ignore")

class SoilAnalyzer:
    def __init__(self):
        """Initialize soil analyzer with pre-trained models ONLY"""
        try:
            script_dir = os.path.dirname(os.path.abspath(__file__))
            
            # Load soil model
            soil_model_path = os.path.join(script_dir, 'models', 'soil_regressor_rf.pkl')
            if not os.path.exists(soil_model_path):
                soil_model_path = os.path.join(script_dir, 'soil_regressor_rf.pkl')
            
            self.soil_model = joblib.load(soil_model_path)
            logging.info("Soil prediction model loaded")
            
            # Load scaler
            scaler_path = os.path.join(script_dir, 'models', 'scaler_soil.pkl')
            if not os.path.exists(scaler_path):
                scaler_path = os.path.join(script_dir, 'scaler_soil.pkl')
            
            self.scaler = joblib.load(scaler_path)
            logging.info("Feature scaler loaded")
            
        except Exception as e:
            logging.error(f"Error loading soil models: {e}")
            raise

    def map_to_model_fields(self, soil_data):
        """Map Supabase field names to model field names"""
        field_mapping = {
            'ph_level': 'Soil_pH',
            'temperature': 'Temperature',
            'moisture': 'Moisture',
            'nitrogen': 'N',
            'phosphorus': 'P',
            'potassium': 'K'
        }
        
        mapped_data = {}
        for supabase_field, model_field in field_mapping.items():
            if supabase_field in soil_data:
                mapped_data[model_field] = soil_data[supabase_field]
            else:
                raise KeyError(f"Missing required field: {supabase_field}")
        
        return mapped_data
    
    # CALCULATING MODEL CONFIDENCE
    def calculate_model_confidence(self, X_soil_scaled):
        """Calculate real confidence score with proper error handling"""
        try:
            
            tree_predictions = []
            for tree in self.soil_model.estimators_:
                pred = tree.predict(X_soil_scaled)[0]
                tree_predictions.append(pred)
            
            
            std_dev = np.std(tree_predictions)
            mean_pred = np.mean(tree_predictions)
            
           
            if std_dev == 0:
                return 1.0
            if mean_pred == 0:
                cv = std_dev
            else:
                cv = std_dev / abs(mean_pred)
            
            
            confidence = 1.0 / (1.0 + cv)
            
            logging.info(f"Model confidence calculation: mean={mean_pred:.2f}, std={std_dev:.2f}, cv={cv:.3f}, confidence={confidence:.3f}")
            
            return float(confidence)
            
        except Exception as e:
            logging.error(f"FATAL: Confidence calculation failed: {e}")
            raise ValueError(f"Cannot calculate confidence: {str(e)}")
    

    def categorize_soil(self, soil_quality):
        """Simple categorization based on pure model score"""
        if soil_quality >= 90: 
            return "Excellent"
        elif soil_quality >= 80: 
            return "Good"
        elif soil_quality >= 60: 
            return "Average"
        elif soil_quality >= 40:  
            return "Poor"
        else: 
            return "Very Poor"

    def analyze_soil(self, soil_data, optimal_ranges):
        """Perform soil analysis using optimal_ranges from database"""
        start_time = time.time()
        try:
            logging.info("Making soil quality prediction...")
            
            # Map fields
            mapped_data = self.map_to_model_fields(soil_data)
            
            # Prepare features for model
            model_feature_names = ["Soil_pH", "Temperature", "Moisture", "N", "P", "K"]
            X_soil = np.array([[mapped_data[feature] for feature in model_feature_names]])
            
            # Scale and predict
            X_soil_scaled = self.scaler.transform(X_soil)
            soil_quality = self.soil_model.predict(X_soil_scaled)[0]
            
            # Calculate confidence
            confidence_score = self.calculate_model_confidence(X_soil_scaled)
            
            # Get soil status based on pure model prediction
            soil_status = self.categorize_soil(soil_quality)
            
            # Generate issues and recommendations
            issues = self.detect_soil_issues(soil_data, optimal_ranges)
            recommendations = self.generate_recommendations(soil_data, optimal_ranges)
            
            inference_time = time.time() - start_time
            
            logging.info(f"Soil analysis complete: {soil_status} (Quality Score: {soil_quality:.1f})")
            
            # SIMPLIFIED RESULT - Only absolutely essential fields
            result = {
                'success': True,
                'soil_status': soil_status,
                'soil_quality_score': float(soil_quality),
                'confidence_score': float(confidence_score),
                'soil_issues': issues,
                'recommendations': recommendations
            }
            
            return result
            
        except Exception as e:
            logging.error(f"Soil analysis error: {e}")
            import traceback
            traceback.print_exc()
            return {
                'success': False,
                'error': f"Soil analysis failed: {str(e)}"
            }

    def detect_soil_issues(self, soil_data, optimal_ranges):
        """Detect soil issues using optimal_ranges from database"""
        issues = []
        
        # Check for dry soil first - CRITICAL for NPK reliability
        current_moisture = soil_data.get('moisture', 0)
        MOISTURE_THRESHOLD = 20  # Minimum moisture % for reliable NPK reading
        
        if current_moisture < MOISTURE_THRESHOLD:
            issues.append(f"Soil is too dry for reliable NPK measurement ({current_moisture}%). Moisturize to at least {MOISTURE_THRESHOLD}% before interpreting nutrient levels.")
            unreliable_npk = True
        else:
            unreliable_npk = False
        
        param_names = {
            'ph_level': 'Soil pH',
            'temperature': 'Temperature',
            'moisture': 'Moisture',
            'nitrogen': 'Nitrogen',
            'phosphorus': 'Phosphorus',
            'potassium': 'Potassium'
        }
        
        for param, config in optimal_ranges.items():
            if param in soil_data:
                value = soil_data[param]
                optimal_min, optimal_max = config['optimal']
                unit = config.get('unit', '')
                
                display_name = param_names.get(param, param.capitalize())
                
                # Special handling for NPK when soil is dry
                if unreliable_npk and param in ['nitrogen', 'phosphorus', 'potassium']:
                    issues.append(f"{display_name} reading ({value}{unit}) may be inaccurate due to dry soil. Remeasure after moistening.")
                    continue  # Skip further checks for this parameter
                
                if value < optimal_min:
                    issues.append(f"{display_name} is too low ({value}{unit}) - optimal range: {optimal_min}-{optimal_max}{unit}")
                elif value > optimal_max:
                    issues.append(f"{display_name} is too high ({value}{unit}) - optimal range: {optimal_min}-{optimal_max}{unit}")
        
        if not issues:
            issues = ["All soil parameters are within optimal ranges"]
        
        return issues

    def generate_recommendations(self, soil_data, optimal_ranges):
        """Generate recommendations using optimal_ranges from database"""
        recommendations = []
        
        # Validate optimal_ranges structure
        required_params = ['ph_level', 'temperature', 'moisture', 'nitrogen', 'phosphorus', 'potassium', 'moisture_threshold']
        for param in required_params:
            if param not in optimal_ranges:
                raise ValueError(f"Optimal range for {param} not provided from database")
        
        # Retrieve current values
        current_ph = soil_data.get('ph_level', 0)
        current_temp = soil_data.get('temperature', 0)
        current_moisture = soil_data.get('moisture', 0)
        current_n = soil_data.get('nitrogen', 0)
        current_p = soil_data.get('phosphorus', 0)
        current_k = soil_data.get('potassium', 0)
        
        # Retrieve optimal ranges from database
        ph_config = optimal_ranges['ph_level']
        temp_config = optimal_ranges['temperature']
        moisture_config = optimal_ranges['moisture']
        n_config = optimal_ranges['nitrogen']
        p_config = optimal_ranges['phosphorus']
        k_config = optimal_ranges['potassium']
        moisture_th = optimal_ranges['moisture_threshold']
        
        ph_optimal = ph_config['optimal']
        temp_optimal = temp_config['optimal']
        moisture_optimal = moisture_config['optimal']
        n_optimal = n_config['optimal']
        p_optimal = p_config['optimal']
        k_optimal = k_config['optimal']
        moisture_th_optimal = moisture_th['optimal']
        
        # Get units from config
        ph_unit = ph_config.get('unit', 'pH')
        temp_unit = temp_config.get('unit', '°C')
        moisture_unit = moisture_config.get('unit', '%')
        n_unit = n_config.get('unit', 'ppm')
        p_unit = p_config.get('unit', 'ppm')
        k_unit = k_config.get('unit', 'ppm')
        
        # MOISTURE GATEKEEPER LOGIC - MUST BE FIRST
        MOISTURE_THRESHOLD = moisture_th_optimal[0]  # Minimum for reliable NPK
        
        if current_moisture < MOISTURE_THRESHOLD:
            recommendations.append(f"URGENT: Soil too dry for NPK measurement - Moisturize soil to at least {MOISTURE_THRESHOLD}{moisture_unit} and retake readings. Current NPK values ({current_n}/{current_p}/{current_k} ppm) may be inaccurate.")
            skip_npk_recommendations = True
        else:
            skip_npk_recommendations = False
        
        # pH recommendations (ALWAYS check pH first - it affects nutrient availability)
        if current_ph < ph_optimal[0]:
            recommendations.append(f"Apply agricultural lime to raise soil pH from {current_ph}{ph_unit} to optimal {ph_optimal[0]}-{ph_optimal[1]}{ph_unit}. Low pH locks out nutrients.")
        elif current_ph > ph_optimal[1]:
            recommendations.append(f"Apply elemental sulfur to lower soil pH from {current_ph}{ph_unit} to optimal {ph_optimal[0]}-{ph_optimal[1]}{ph_unit}. High pH locks out nutrients.")
        
        # Temperature recommendations
        if current_temp < temp_optimal[0]:
            recommendations.append(f"Use row covers or black plastic mulch to increase soil temperature from {current_temp}{temp_unit} to optimal {temp_optimal[0]}-{temp_optimal[1]}{temp_unit}")
        elif current_temp > temp_optimal[1]:
            recommendations.append(f"Provide shade or use reflective mulch to reduce soil temperature from {current_temp}{temp_unit} to optimal {temp_optimal[1]}{temp_unit}")
        
        # Moisture recommendations (general, not the gatekeeper warning)
        if not skip_npk_recommendations:
            if current_moisture < moisture_optimal[0]:
                recommendations.append(f"Increase watering frequency to raise moisture from {current_moisture}{moisture_unit} to optimal {moisture_optimal[0]}-{moisture_optimal[1]}{moisture_unit}")
            elif current_moisture > moisture_optimal[1]:
                recommendations.append(f"Improve drainage to reduce moisture from {current_moisture}{moisture_unit} to optimal {moisture_optimal[1]}{moisture_unit}")
        
        # Nutrient recommendations - ONLY if soil is moist enough and pH is checked
        if not skip_npk_recommendations:
            # Check if pH is problematic first
            pH_problem = current_ph < ph_optimal[0] or current_ph > ph_optimal[1]
            
            if pH_problem:
                # If pH is wrong, nutrients might be locked out regardless of NPK readings
                recommendations.append(f"Fix pH before fertilizing - Current pH ({current_ph}{ph_unit}) makes nutrients unavailable. Adjust pH to {ph_optimal[0]}-{ph_optimal[1]}{ph_unit} first.")
            else:
                # Only provide nutrient recommendations if pH is okay
                if current_n < n_optimal[0]:
                    deficit = n_optimal[0] - current_n
                    recommendations.append(f"Apply nitrogen-rich fertilizer (urea) - Estimated deficit: {deficit:.0f}{n_unit}")
                elif current_n > n_optimal[1]:
                    recommendations.append(f"Reduce nitrogen - Current {current_n}{n_unit} may cause excessive growth")
                
                if current_p < p_optimal[0]:
                    deficit = p_optimal[0] - current_p
                    recommendations.append(f"Apply phosphorus fertilizer (superphosphate) - Estimated deficit: {deficit:.0f}{p_unit}")
                elif current_p > p_optimal[1]:
                    recommendations.append(f"Avoid additional phosphorus this season")
                
                if current_k < k_optimal[0]:
                    deficit = k_optimal[0] - current_k
                    recommendations.append(f"Apply potassium fertilizer (potassium sulfate) - Estimated deficit: {deficit:.0f}{k_unit}")
                elif current_k > k_optimal[1]:
                    recommendations.append(f"Reduce potassium application")
        
        if not recommendations:
            recommendations = [
                "Soil conditions are good for tomato growth",
                "Continue regular monitoring",
                "Apply fertilizer according to plant growth stage"
            ]
        
        # Ensure moisture warning is always first if present
        moisture_warnings = [r for r in recommendations if "dry for NPK" in r]
        other_recommendations = [r for r in recommendations if "dry for NPK" not in r]
        
        return moisture_warnings + other_recommendations

def main():
    """Main function for soil prediction"""
    try:
        if len(sys.argv) < 2:
            result = {
                'success': False,
                'error': 'Input data argument required'
            }
            print(json.dumps(result))
            return
        
        input_data = json.loads(sys.argv[1])
        soil_data = input_data.get('soil_data', {})
        optimal_ranges = input_data.get('optimal_ranges', {})
        user_id = input_data.get('user_id', 'unknown')
        soil_id = input_data.get('soil_id', 'unknown')
        
        logging.info(f"Analyzing soil for user: {user_id}")
        
        if not soil_data:
            result = {
                'success': False,
                'error': 'No soil data provided'
            }
            print(json.dumps(result))
            return
        
        if not optimal_ranges:
            result = {
                'success': False,
                'error': 'No optimal ranges provided from database'
            }
            print(json.dumps(result))
            return
        
        analyzer = SoilAnalyzer()
        result = analyzer.analyze_soil(soil_data, optimal_ranges)
        result['user_id'] = user_id
        result['soil_id'] = soil_id
        
        logging.info(f"Soil prediction completed for user: {user_id}")
        print(json.dumps(result, default=str))
        
    except Exception as e:
        result = {
            'success': False,
            'error': f"Soil prediction failed: {str(e)}"
        }
        print(json.dumps(result))

if __name__ == "__main__":
    main()