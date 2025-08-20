"""
Unit tests for SEC data ingestion module
"""
import pytest
from unittest.mock import Mock, patch
from src.ingest.fetch_sec import get_ticker_cik_map, normalize_companyfacts


def test_get_ticker_cik_map():
    """Test ticker to CIK mapping functionality"""
    mock_response = {
        "0": {"cik_str": 320193, "ticker": "AAPL", "title": "Apple Inc."},
        "1": {"cik_str": 789019, "ticker": "MSFT", "title": "Microsoft Corp"}
    }
    
    with patch('src.ingest.fetch_sec.fetch_json', return_value=mock_response):
        result = get_ticker_cik_map()
        
    assert result["AAPL"] == "0000320193"
    assert result["MSFT"] == "0000789019"


def test_normalize_companyfacts_empty():
    """Test handling of empty facts data"""
    result = normalize_companyfacts("0000320193", "AAPL", {})
    assert result == []


def test_normalize_companyfacts_with_data():
    """Test processing of company facts data"""
    facts_data = {
        "facts": {
            "us-gaap": {
                "Revenues": {
                    "units": {
                        "USD": [
                            {
                                "end": "2023-12-31",
                                "val": 1000000,
                                "accn": "123456",
                                "fy": 2023,
                                "fp": "FY"
                            }
                        ]
                    }
                }
            }
        }
    }
    
    result = normalize_companyfacts("0000320193", "AAPL", facts_data)
    
    assert len(result) == 1
    assert result[0]["cik"] == "0000320193"
    assert result[0]["ticker"] == "AAPL"
    assert result[0]["concept"] == "us-gaap:Revenues"
    assert result[0]["val"] == 1000000