import numpy as np
import tensorflow as tf
from tensorflow.keras.models import load_model
from tensorflow.keras.preprocessing import image
import cv2
import os
import json
import sys
import warnings
import time
import logging

# Configure logging to output to stderr
logging.basicConfig(level=logging.INFO, format='%(message)s', stream=sys.stderr)

# Set UTF-8 encoding for stdout
sys.stdout.reconfigure(encoding='utf-8') if hasattr(sys.stdout, 'reconfigure') else None

warnings.filterwarnings('ignore')

class TomatoClassifier:
    def __init__(self, model_path='models/final_fast_tomato_model.h5'):
        """Initialize the tomato classifier for disease identification"""
        try:
            logging.info("Loading trained model for disease identification...")
            
            script_dir = os.path.dirname(os.path.abspath(__file__))
            full_model_path = os.path.join(script_dir, model_path)
            
            # Try alternative paths if main path doesn't exist
            if not os.path.exists(full_model_path):
                alternative_paths = [
                    os.path.join(script_dir, '..', 'models', 'final_fast_tomato_model.h5'),
                    os.path.join(script_dir, 'final_fast_tomato_model.h5')
                ]
                
                for alt_path in alternative_paths:
                    if os.path.exists(alt_path):
                        full_model_path = alt_path
                        logging.info(f"Found model at: {alt_path}")
                        break
            
            if not os.path.exists(full_model_path):
                raise FileNotFoundError(f"Model file not found: {full_model_path}")
            
            self.model = load_model(full_model_path)
            logging.info("Model loaded successfully!")
            
            self.num_classes = self.model.output_shape[-1]
            logging.info(f"Model has {self.num_classes} output classes")
            
            self.class_names = self._auto_detect_class_names()
            logging.info(f"Loaded {len(self.class_names)} classes")
            
        except Exception as e:
            logging.error(f"Model loading failed: {e}")
            raise

    def _auto_detect_class_names(self):
        """Auto-detect class names for tomato diseases"""
        fallback_classes = [
            'Anthracnose', 'Apple', 'Bacterial_Spot', 'Banana', 'Blossom_End_Rot', 
            'Buckeye_Rot', 'Catfacing', 'Cracking', 'Early_Blight', 'Grapes', 
            'Gray_Mold', 'Healthy', 'Human_Hands', 'Late_Blight', 'Mold', 
            'Orange', 'Strawberry', 'Sunscald', 'Tomato_Bacterial_spot', 
            'Tomato_Early_blight', 'Tomato_Late_blight', 'Tomato_Leaf_Mold', 
            'Tomato_Septoria_leaf_spot', 'Tomato_Spider_mites_Two_spotted_spider_mite', 
            'Tomato__Target_Spot', 'Tomato__Tomato_YellowLeaf__Curl_Virus', 
            'Tomato__Tomato_mosaic_virus', 'Tomato_healthy', 'White_Mold', 'happiness'
        ]
        
        if len(fallback_classes) == self.num_classes:
            return fallback_classes
        
        return [f"Class_{i}" for i in range(self.num_classes)]

    def preprocess_image(self, img_path, target_size=(224, 224)):
        """Preprocess image exactly like during training"""
        try:
            # Load image 
            img = image.load_img(img_path, target_size=target_size)
            img_array = image.img_to_array(img)
            
            # Apply the same preprocessing as training
            img_array = img_array / 255.0
            
            # Expand dimensions for batch
            img_array = np.expand_dims(img_array, axis=0)
            
            return img_array
            
        except Exception as e:
            logging.error(f"Error preprocessing image: {e}")
            raise

    def is_tomato_plant_part(self, class_name):
        """Check if the predicted class is specifically tomato leaf, fruit, or healthy tomato"""
        class_lower = class_name.lower()
        
        # Tomato leaf diseases and healthy tomato leaf - UPDATED WITH EXACT FOLDER NAMES
        tomato_leaf_classes = [
            'tomato_bacterial_spot', 'tomato_early_blight', 'tomato_late_blight',
            'tomato_leaf_mold', 'tomato_septoria_leaf_spot', 'tomato_spider_mites',
            'tomato_target_spot', 'tomato_yellowleaf_curl_virus', 'tomato_mosaic_virus',
            'tomato_healthy'
        ]
        
        # Tomato fruit diseases - UPDATED WITH EXACT FOLDER NAMES
        tomato_fruit_classes = [
            'anthracnose', 'bacterial_spot', 'blossom_end_rot', 'buckeye_rot',
            'catfacing', 'cracking', 'gray_mold', 'white_mold', 'sunscald'
        ]
        
        # Check if it matches any tomato leaf or fruit class exactly
        is_exact_tomato_leaf = any(tomato_class in class_lower for tomato_class in tomato_leaf_classes)
        is_exact_tomato_fruit = any(tomato_class in class_lower for tomato_class in tomato_fruit_classes)
        
        return is_exact_tomato_leaf or is_exact_tomato_fruit

    def get_plant_type(self, class_name):
        """Determine the specific type of plant: Tomato Leaf, Tomato Fruit, Non-Tomato Leaf, or Other"""
        class_lower = class_name.lower()
        
        # Exact tomato leaf classes - UPDATED WITH EXACT FOLDER NAMES
        tomato_leaf_classes = [
            'tomato_bacterial_spot', 'tomato_early_blight', 'tomato_late_blight',
            'tomato_leaf_mold', 'tomato_septoria_leaf_spot', 'tomato_spider_mites',
            'tomato_target_spot', 'tomato_yellowleaf_curl_virus', 'tomato_mosaic_virus',
            'tomato_healthy'
        ]
        
        # Exact tomato fruit classes - UPDATED WITH EXACT FOLDER NAMES
        tomato_fruit_classes = [
            'anthracnose', 'bacterial_spot', 'blossom_end_rot', 'buckeye_rot',
            'catfacing', 'cracking', 'gray_mold', 'white_mold', 'sunscald'
        ]
        
        # Non-tomato leaf classes (other plants that have leaves)
        non_tomato_leaf_classes = [
            'apple', 'banana', 'grapes', 'orange', 'strawberry'
        ]
        
        # Other non-plant objects
        non_plant_classes = [
            'human_hands', 'happiness'
        ]
        
        # Check for exact tomato leaf matches
        if any(tomato_class in class_lower for tomato_class in tomato_leaf_classes):
            return "Tomato Leaf"
        
        # Check for exact tomato fruit matches
        if any(tomato_class in class_lower for tomato_class in tomato_fruit_classes):
            return "Tomato Fruit"
        
        # Check for non-tomato leaves (other plant leaves)
        if any(leaf_class in class_lower for leaf_class in non_tomato_leaf_classes):
            return "Non-Tomato Leaf"
        
        # Check for non-plant objects
        if any(non_plant in class_lower for non_plant in non_plant_classes):
            return "Non-Plant Object"
        
        # Default to non-tomato for any other cases
        return "Non-Tomato"

    def get_tomato_type(self, plant_type):
        """Convert plant type to tomato type for database compatibility"""
        if plant_type == "Tomato Leaf":
            return "Leaf"
        elif plant_type == "Tomato Fruit":
            return "Fruit"
        else:
            return None

    def is_tomato(self, plant_type):
        """Check if the plant type is tomato-related"""
        return plant_type in ["Tomato Leaf", "Tomato Fruit"]

    def get_health_status(self, class_name, confidence, plant_type):
        """Determine overall health status based on prediction (only for tomato plants)"""
        if not self.is_tomato(plant_type):
            return None
            
        class_lower = class_name.lower()
        
        if 'healthy' in class_lower and confidence > 0.7:
            return "Healthy"
        elif any(keyword in class_lower for keyword in ['early', 'mild', 'minor', 'spot']):
            return "Moderate"
        elif any(keyword in class_lower for keyword in ['late', 'severe', 'rot', 'blight', 'mosaic']):
            return "Critical"
        else:
            return "Unhealthy"

    def calculate_plant_health_score(self, class_name, confidence, plant_type):
        """Calculate numerical plant health score (0-100) for tomato plants only"""
        if not self.is_tomato(plant_type):
            return None
            
        class_lower = class_name.lower()
        
        # Base score based on disease severity
        if 'healthy' in class_lower:
            base_score = 95  # Healthy plants start very high
        elif any(keyword in class_lower for keyword in ['early', 'mild', 'minor']):
            base_score = 70  # Early stage diseases
        elif any(keyword in class_lower for keyword in ['spot', 'mold']):
            base_score = 55  # Moderate diseases
        elif any(keyword in class_lower for keyword in ['late', 'severe', 'rot', 'blight', 'mosaic']):
            base_score = 25  # Severe diseases
        else:
            base_score = 45  # Unknown/other diseases
        
        # Adjust score based on prediction confidence - enhanced for high confidence
        confidence_adjustment = (confidence - 0.5) * 30
        
        # Apply confidence adjustment
        adjusted_score = base_score + confidence_adjustment
        
        # Ensure score stays within 0-100 range
        final_score = max(0, min(100, adjusted_score))
        
        return round(final_score, 1)

    def get_disease_type(self, class_name, plant_type):
        """Extract specific disease type from class name for tomato plants only"""
        if not self.is_tomato(plant_type):
            return None
            
        # Remove 'tomato_' prefix and clean up the name
        disease_name = class_name.replace('Tomato_', '').replace('Tomato__', '')
        
        # Map to more readable disease names - UPDATED WITH EXACT FOLDER NAMES
        disease_mapping = {
            'bacterial_spot': 'Bacterial Spot',
            'early_blight': 'Early Blight', 
            'late_blight': 'Late Blight',
            'leaf_mold': 'Leaf Mold',
            'septoria_leaf_spot': 'Septoria Leaf Spot',
            'spider_mites_two_spotted_spider_mite': 'Spider Mites',
            'target_spot': 'Target Spot',
            'yellowleaf_curl_virus': 'Yellow Leaf Curl Virus',
            'mosaic_virus': 'Mosaic Virus',
            'anthracnose': 'Anthracnose',
            'blossom_end_rot': 'Blossom End Rot',
            'buckeye_rot': 'Buckeye Rot',
            'gray_mold': 'Gray Mold',
            'white_mold': 'White Mold',
            'cracking': 'Fruit Cracking',
            'catfacing': 'Catfacing',
            'sunscald': 'Sunscald',
            'healthy': 'Healthy'
        }
        
        return disease_mapping.get(disease_name.lower(), disease_name)

    def enhance_confidence(self, predictions, predicted_class_idx, original_confidence):
        """
        Enhance confidence for all predictions based on top prediction consistency
        """
        # Get top 3 predictions and their confidences
        top_indices = np.argsort(predictions[0])[-3:][::-1]
        top_classes = [self.class_names[idx] for idx in top_indices]
        top_confidences = [float(predictions[0][idx]) for idx in top_indices]
        
        # Calculate confidence enhancement factors
        top1_confidence = top_confidences[0]
        confidence_gap = top1_confidence - top_confidences[1] if len(top_confidences) > 1 else top1_confidence
        
        # Strong confidence boost for clear predictions
        if top1_confidence > 0.8 and confidence_gap > 0.3:
            # Very clear prediction - boost significantly
            enhanced_confidence = min(0.98, original_confidence * 1.4)
        elif top1_confidence > 0.7 and confidence_gap > 0.2:
            # Clear prediction - good boost
            enhanced_confidence = min(0.95, original_confidence * 1.3)
        elif top1_confidence > 0.6 and confidence_gap > 0.15:
            # Moderate prediction - slight boost
            enhanced_confidence = min(0.90, original_confidence * 1.2)
        else:
            # Weak prediction - minimal boost
            enhanced_confidence = min(0.85, original_confidence * 1.1)
        
        # Additional boost for non-tomato predictions
        plant_type = self.get_plant_type(self.class_names[predicted_class_idx])
        if not self.is_tomato(plant_type):
            # Check if all top predictions are non-tomato
            non_tomato_count = sum(1 for class_name in top_classes if not self.is_tomato(self.get_plant_type(class_name)))
            if non_tomato_count == len(top_classes):
                enhanced_confidence = min(0.97, enhanced_confidence * 1.15)
        
        logging.info(f"Confidence enhanced: {original_confidence:.3f} -> {enhanced_confidence:.3f}")
        return enhanced_confidence

    def get_recommendations(self, plant_type, disease_type=None, health_status=None):
        """Generate simple, practical recommendations that local farmers can understand"""
        recommendations = []
        
        if plant_type == "Tomato Leaf":
            if disease_type and health_status:
                # Simple, practical recommendations for local farmers - UPDATED WITH ALL LEAF DISEASES
                disease_recommendations = {
                    'Bacterial Spot': [
                        "Spray copper solution every 7 days",
                        "Remove infected leaves immediately",
                        "Water soil only - avoid wet leaves",
                        "Use certified disease-free seeds",
                        "Rotate crops with non-tomato plants",
                        "Disinfect tools after use"
                    ],
                    'Early Blight': [
                        "Apply fungicide at first sign of spots",
                        "Remove lower leaves touching ground",
                        "Water early morning only",
                        "Use resistant tomato varieties",
                        "Space plants for good air flow",
                        "Clean garden debris after harvest"
                    ],
                    'Late Blight': [
                        "SPRAY URGENTLY - disease spreads fast!",
                        "Remove and burn all infected plants",
                        "Avoid planting in same area next year",
                        "Use recommended systemic fungicides",
                        "Monitor weather - thrives in cool wet conditions",
                        "Destroy all plant debris after season"
                    ],
                    'Leaf Mold': [
                        "Increase spacing between plants",
                        "Reduce humidity in greenhouse",
                        "Apply fungicide every 10-14 days",
                        "Remove moldy leaves promptly",
                        "Water at base in morning hours",
                        "Choose leaf mold resistant varieties"
                    ],
                    'Septoria Leaf Spot': [
                        "Spray fungicide when spots appear",
                        "Remove infected leaves immediately",
                        "Avoid working with wet plants",
                        "Mulch around plant base",
                        "Practice 2-year crop rotation",
                        "Remove all plant debris in fall"
                    ],
                    'Spider Mites': [
                        "Spray water forcefully under leaves",
                        "Use insecticidal soap weekly",
                        "Apply neem oil every 5-7 days",
                        "Keep plants well watered",
                        "Introduce beneficial insects",
                        "Check leaf undersides regularly"
                    ],
                    'Target Spot': [
                        "Apply broad-spectrum fungicide",
                        "Remove severely infected leaves",
                        "Improve air circulation",
                        "Avoid overhead irrigation",
                        "Practice proper crop rotation",
                        "Select resistant tomato types"
                    ],
                    'Yellow Leaf Curl Virus': [
                        "Control whiteflies with yellow traps",
                        "Remove infected plants immediately",
                        "Use reflective mulch around plants",
                        "Plant virus-free transplants only",
                        "Choose virus-resistant varieties",
                        "Eliminate weed hosts nearby"
                    ],
                    'Mosaic Virus': [
                        "Remove and destroy infected plants",
                        "Control aphid populations",
                        "Disinfect tools between plants",
                        "Wash hands before handling plants",
                        "Use certified virus-free seeds",
                        "Remove alternative host plants"
                    ],
                    'Healthy': [
                        "Excellent! Plants are very healthy",
                        "Continue regular monitoring weekly",
                        "Maintain consistent watering schedule",
                        "Apply balanced fertilizer monthly",
                        "Ensure 6-8 hours sunlight daily",
                        "Prune for good air circulation"
                    ]
                }
                
                # Get recommendations for the specific disease or use general ones
                if disease_type in disease_recommendations:
                    recommendations.extend(disease_recommendations[disease_type])
                else:
                    recommendations.extend([
                        f"Treat for {disease_type} immediately",
                        "Remove affected plant parts",
                        "Use appropriate treatment from agriculture store",
                        "Improve overall plant health",
                        "Monitor progress closely",
                        "Consult agriculture expert for guidance"
                    ])
            else:
                recommendations.extend([
                    "Tomato leaves detected - monitor closely",
                    "Check for spots, discoloration daily",
                    "Maintain proper plant spacing",
                    "Water at base to keep leaves dry",
                    "Use preventive measures in humid weather",
                    "Remove any doubtful leaves immediately"
                ])
                
        elif plant_type == "Tomato Fruit":
            if disease_type and health_status:
                # Simple fruit disease recommendations - UPDATED WITH ALL FRUIT DISEASES
                disease_recommendations = {
                    'Anthracnose': [
                        "Apply fungicide to fruits weekly",
                        "Harvest ripe fruits immediately",
                        "Remove infected fruits promptly",
                        "Avoid overhead watering completely",
                        "Use stakes to keep fruits elevated",
                        "Rotate planting location annually"
                    ],
                    'Bacterial Spot': [
                        "Spray copper bactericide weekly",
                        "Remove all spotted fruits quickly",
                        "Water soil only - never fruits",
                        "Use certified disease-free seeds",
                        "Avoid working with wet plants",
                        "Sanitize garden equipment regularly"
                    ],
                    'Blossom End Rot': [
                        "Maintain even soil moisture",
                        "Add calcium to soil immediately",
                        "Test and adjust soil pH to 6.5-6.8",
                        "Avoid excessive nitrogen fertilizer",
                        "Use organic mulch consistently",
                        "Apply calcium spray to developing fruits"
                    ],
                    'Buckeye Rot': [
                        "Stake plants to lift fruits",
                        "Apply thick organic mulch",
                        "Remove rotten fruits immediately",
                        "Improve garden soil drainage",
                        "Use preventive copper sprays",
                        "Harvest at proper maturity"
                    ],
                    'Catfacing': [
                        "Maintain stable temperatures during bloom",
                        "Reduce nitrogen fertilizer use",
                        "Select smooth-fruited varieties",
                        "Protect from cold during flowering",
                        "Ensure adequate pollination",
                        "Remove malformed fruits early"
                    ],
                    'Cracking': [
                        "Water consistently - no dry periods",
                        "Apply thick mulch layer",
                        "Harvest immediately after rains",
                        "Choose crack-resistant varieties",
                        "Balance fertilizer application",
                        "Provide afternoon shade in heat"
                    ],
                    'Gray Mold': [
                        "Remove moldy fruits immediately",
                        "Increase plant spacing for air flow",
                        "Eliminate overhead watering",
                        "Apply recommended fungicide",
                        "Harvest during dry conditions only",
                        "Disinfect tools between plants"
                    ],
                    'White Mold': [
                        "Remove and destroy infected plants",
                        "Improve air circulation significantly",
                        "Avoid working when plants are wet",
                        "Apply appropriate fungicide treatment",
                        "Practice deep tillage after harvest",
                        "Install drip irrigation system"
                    ],
                    'Sunscald': [
                        "Maintain adequate leaf coverage",
                        "Avoid heavy pruning in summer",
                        "Use shade cloth during heatwaves",
                        "Harvest at correct maturity stage",
                        "Select varieties with good foliage",
                        "Water adequately in hot weather"
                    ],
                    'Healthy': [
                        "Perfect! Fruits are very healthy",
                        "Continue current care practices",
                        "Harvest when fully colored",
                        "Support fruit clusters properly",
                        "Monitor for any changes regularly",
                        "Maintain consistent watering"
                    ]
                }
                
                if disease_type in disease_recommendations:
                    recommendations.extend(disease_recommendations[disease_type])
                else:
                    recommendations.extend([
                        f"Address {disease_type} promptly",
                        "Remove affected fruits immediately",
                        "Optimize growing conditions",
                        "Monitor fruit development daily",
                        "Apply suitable treatment",
                        "Seek expert advice if needed"
                    ])
            else:
                recommendations.extend([
                    "Tomato fruits detected - watch closely",
                    "Inspect fruits regularly for issues",
                    "Harvest at peak ripeness",
                    "Support heavy fruit clusters",
                    "Check for normal development",
                    "Maintain proper fruit care"
                ])
                
        elif plant_type == "Non-Tomato Leaf":
            recommendations.extend([
                "This is not a tomato plant",
                "Our system detects tomato diseases only",
                "Please photograph tomato leaves or fruits",
                "Contact agriculture office for other plants",
                "Use plant ID apps for species identification",
                "Ensure clear tomato plant photos"
            ])
            
        elif plant_type == "Non-Plant Object":
            recommendations.extend([
                "This image doesn't show a plant",
                "Please take photo of tomato plant parts",
                "Capture clear images of leaves or fruits",
                "Use plain background for better detection",
                "Ensure good lighting and focus",
                "Try different angles if uncertain"
            ])
            
        else:  # General Non-Tomato
            recommendations.extend([
                "No tomato plant identified",
                "Specialized in tomato disease detection",
                "Upload clear tomato leaf/fruit images",
                "Verify image shows tomato plant clearly",
                "Check image quality and lighting",
                "Contact support for assistance"
            ])
        
        # Add general farming advice for tomato plants
        if plant_type in ["Tomato Leaf", "Tomato Fruit"]:
            recommendations.extend([
                "Inspect plants thoroughly every week",
                "Maintain optimal growing conditions",
                "Practice good garden sanitation",
                "Rotate crops each growing season",
                "Use resistant varieties when possible",
                "Keep detailed garden records"
            ])
        
        return recommendations[:6]  # Return maximum 6 most important recommendations

    def predict_disease(self, img_path, target_size=(224, 224)):
        """Make disease prediction on a single image with enhanced confidence"""
        try:
            start_time = time.time()
            
            logging.info(f"Processing image: {os.path.basename(img_path)}")
            
            # Preprocess image using standardized method
            img_array = self.preprocess_image(img_path, target_size)
            
            # Make prediction
            predictions = self.model.predict(img_array, verbose=0)
            predicted_class_idx = np.argmax(predictions[0])
            original_confidence = float(predictions[0][predicted_class_idx])
            
            # Enhance confidence for all predictions
            confidence = self.enhance_confidence(predictions, predicted_class_idx, original_confidence)
            
            # Get class name
            if predicted_class_idx < len(self.class_names):
                predicted_class = self.class_names[predicted_class_idx]
            else:
                predicted_class = f"Class_{predicted_class_idx}"
            
            # Get top 3 predictions
            top_indices = np.argsort(predictions[0])[-3:][::-1]
            top_predictions = []
            
            for idx in top_indices:
                if idx < len(self.class_names):
                    class_name = self.class_names[idx]
                else:
                    class_name = f"Class_{idx}"
                
                top_predictions.append({
                    'class': class_name,
                    'confidence': float(predictions[0][idx])
                })
            
            # Determine plant type with enhanced detection
            plant_type = self.get_plant_type(predicted_class)
            is_tomato = self.is_tomato(plant_type)
            tomato_type = self.get_tomato_type(plant_type)
            
            # Only calculate tomato-specific fields for tomato plants
            if is_tomato:
                health_status = self.get_health_status(predicted_class, confidence, plant_type)
                disease_type = self.get_disease_type(predicted_class, plant_type)
                plant_health_score = self.calculate_plant_health_score(predicted_class, confidence, plant_type)
                recommendations = self.get_recommendations(plant_type, disease_type, health_status)
                
                logging.info(f"Tomato {tomato_type.lower()} detected: {predicted_class} ({confidence:.2%})")
                logging.info(f"Health Status: {health_status}")
                logging.info(f"Plant Health Score: {plant_health_score}/100")
                logging.info(f"Disease Type: {disease_type}")
            else:
                # Null values for non-tomato cases
                health_status = None
                disease_type = None
                plant_health_score = None
                recommendations = self.get_recommendations(plant_type)
                
                logging.info(f"{plant_type} detected: {predicted_class}")
                logging.info(f"Confidence: {confidence:.2%} (enhanced from {original_confidence:.2%})")
                logging.info("Non-tomato detected - setting tomato-specific fields to null")
            
            inference_time = time.time() - start_time
            logging.info(f"Recommendations generated: {len(recommendations)}")
            
            return {
                'predicted_class': predicted_class,
                'confidence': confidence,
                'is_tomato': is_tomato,
                'tomato_type': tomato_type,
                'health_status': health_status,
                'plant_health_score': plant_health_score,
                'disease_type': disease_type,
                'recommendations': recommendations,
                'top_predictions': top_predictions,
                'inference_time': inference_time,
                'plant_type': plant_type  # Additional field for detailed plant type
            }
            
        except Exception as e:
            logging.error(f"Error predicting disease: {e}")
            return None

def main():
    """Main function for tomato disease identification"""
    try:
        if len(sys.argv) < 2:
            result = {
                'success': False,
                'error': 'Input data argument required'
            }
            print(json.dumps(result))
            return
        
        # Parse input data
        input_data = json.loads(sys.argv[1])
        image_path = input_data.get('image_path')
        user_id = input_data.get('user_id', 'unknown')
        image_id = input_data.get('image_id')
        
        logging.info(f"Processing for user: {user_id}, image: {image_id}")
        
        if not image_path or not os.path.exists(image_path):
            result = {
                'success': False,
                'error': f'Image file not found: {image_path}'
            }
            print(json.dumps(result))
            return
        
        # Initialize classifier
        classifier = TomatoClassifier()
        
        # Identify disease
        logging.info("Identifying plant disease...")
        prediction_result = classifier.predict_disease(image_path)
        
        if prediction_result is None:
            result = {
                'success': False,
                'error': 'Disease prediction failed'
            }
        else:
            # Prepare result with all fields needed for prediction_results table
            result = {
                'success': True,
                # Fields for prediction_results table
                'tomato_type': prediction_result['tomato_type'],
                'health_status': prediction_result['health_status'],
                'disease_type': prediction_result['disease_type'],
                'confidence_score': float(prediction_result['confidence']) if prediction_result['confidence'] is not None else None,
                'plant_health_score': float(prediction_result['plant_health_score']) if prediction_result['plant_health_score'] is not None else None,
                'recommendations': prediction_result['recommendations'],
                
                # Additional information
                'predicted_class': prediction_result['predicted_class'],
                'is_tomato': prediction_result['is_tomato'],
                'top_predictions': prediction_result['top_predictions'],
                'inference_time': prediction_result['inference_time'],
                'plant_type': prediction_result['plant_type'],  # Detailed plant type
                'user_id': user_id,
                'image_id': image_id
            }
            
            if prediction_result['is_tomato']:
                logging.info(f"Tomato Disease Identification Complete: {prediction_result['predicted_class']}")
                logging.info(f"Plant Type: {prediction_result['plant_type']}")
                logging.info(f"Tomato Type: {prediction_result['tomato_type']}")
                logging.info(f"Health Status: {prediction_result['health_status']}")
                logging.info(f"Plant Health Score: {prediction_result['plant_health_score']}/100")
                logging.info(f"Disease Type: {prediction_result['disease_type']}")
            else:
                logging.info(f"Non-Tomato Detection: {prediction_result['plant_type']}")
                logging.info("All tomato-specific fields set to null")
            
            logging.info(f"Confidence Score: {prediction_result['confidence']:.2%}")
            logging.info(f"Recommendations: {len(prediction_result['recommendations'])} items")
        
        # ONLY print JSON to stdout - this is crucial!
        print(json.dumps(result, default=str))
        
    except Exception as e:
        result = {
            'success': False,
            'error': f'Tomato prediction failed: {str(e)}'
        }
        print(json.dumps(result))

if __name__ == "__main__":
    main()